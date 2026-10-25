{
  pkgs,
  ...
}:
{
  imports = [ ./netconsole.nix ];

  # Boot/kernel settings shared by every Raspberry Pi storage module (ssd.nix,
  # sd.nix).
  #
  # Pinned to the LTS kernel rather than linuxPackages_latest. coruscant hard-hung
  # with no panic, OOM, under-voltage event or I/O error in its journal on the first
  # boot after a deploy that moved linuxPackages_latest from 7.1.8 to 7.2.2, and the
  # two boots after that failed to stay up past 30-90s. Mainline instability on the
  # Pi 4 (BCM2711) is the prime suspect; 6.18 LTS has none of that history. Revisit
  # once a later mainline has run clean for a while.
  # Analysis: .pi/plans/coruscant-unresponsive-diagnosis.md
  boot.kernelPackages = pkgs.linuxPackages;

  # Kernel/cmdline insurance for the USB root device. On 2026-10-23 coruscant lost
  # writes while reporting success: three store paths ended up 0-byte yet still
  # registered as valid in the Nix DB, and systemd later failed to fork with EIO.
  # The bridge is a Realtek 0bda:9201 (Ugreen) using the flaky UAS driver, with a
  # volatile write cache and no FUA. USB_STORAGE is builtin (CONFIG_USB_STORAGE=y)
  # and USB_UAS is a module, so `u` is safe: the root device still comes up under
  # the bulk-only driver, at some throughput cost a home server will not miss.
  boot.kernelParams = [
    "rootwait"
    "usb-storage.quirks=0bda:9201:u"
    "usbcore.autosuspend=-1"
  ];

  # The Pi 4 has no RTC, and nothing enabled a watchdog, so a frozen kernel
  # stayed frozen until someone pulled the power. bcm2835_wdt is probed on every
  # boot (it appears in the journal as bcm2835-wdt/bcm2835-pm), so let systemd
  # drive it: if the manager stops petting the device, the board reboots itself
  # instead of hanging silently.
  # RebootWatchdogSec is set to 0 to actually disable it. Leaving it unset does NOT
  # disable it — systemd's default is 10 minutes, which bcm2835_wdt cannot hold, so
  # it is silently ignored and gives a false sense of protection (observed on
  # coruscant after a switch that merely removed the setting). A hardware-realistic
  # value would be worse: the chip tops out around 15 s, so it would hard-reset the
  # board mid-shutdown while podman is still stopping Home Assistant. The runtime
  # watchdog plus the canary below are what actually cover the failures seen here.
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "10s";
    RebootWatchdogSec = "0";
  };

  # Same intent on the SCSI side: the enclosure advertises a write-back cache and
  # FUA=0, which is how an fsync() can be acknowledged and then lost on power cut.
  # Write-through costs write bandwidth and removes that window.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="scsi_disk", ATTR{cache_type}="write through"
  '';

  # Storage canary. A systemd runtime watchdog only fires when PID 1 stops petting
  # it, so it would NOT have caught coruscant's actual failure: PID 1 stayed alive
  # and logged "Failed to spawn … Input/output error" while the root silently
  # stopped accepting writes. This does the three things that broke — fork/exec,
  # write, fsync — and only then pets systemd. If any step fails or blocks, the
  # unit stops petting, its watchdog expires, and FailureAction=reboot-force calls
  # reboot(2) directly, which still works when forking is broken.
  #
  # WatchdogSec is 5 min rather than 60 s on purpose: a machine already broken at
  # boot must not reboot-loop faster than you can log in to stop the unit, and
  # detecting silent write loss does not need sub-minute resolution. The in-script
  # grace does the same for explicit probe failures during early boot.
  systemd.services.storage-canary = {
    description = "Storage canary: fork, write, fsync; reboot when any of them fails";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    path = [
      pkgs.coreutils
      pkgs.systemd
      pkgs.util-linux
    ];
    serviceConfig = {
      Type = "notify";
      NotifyAccess = "all";
      WatchdogSec = "300s";
      FailureAction = "reboot-force";
      Restart = "no";
      StateDirectory = "storage-canary";
    };
    script = ''
      probe=/var/lib/storage-canary/probe
      systemd-notify --ready --status="storage canary armed"
      while :; do
        if true && printf '%s\n' "$(date -Is)" > "$probe" && sync -d "$probe"; then
          systemd-notify WATCHDOG=1
        else
          up=$(cut -d. -f1 /proc/uptime)
          if [ "$up" -lt 300 ]; then
            logger -t storage-canary "probe failed at uptime ''${up}s, not rebooting inside the boot grace"
            systemd-notify WATCHDOG=1
          else
            logger -t storage-canary "probe failed at uptime ''${up}s, rebooting"
            exit 1
          fi
        fi
        sleep 20
      done
    '';
  };

  boot.loader.raspberry-pi = {
    bootloader = "kernel";
    # 5 rather than 2: both recent generations can come off the same suspect drive,
    # so a second fallback is worth the ~130 MB of FAT it costs.
    configurationLimit = 5;
  };
  fileSystems."/boot/firmware".neededForBoot = true;

  # TRIM over a USB bridge is a documented way to wedge cheap enclosures, and the
  # gain on a 500G SSD behind USB is marginal next to losing the root device.
  # Re-enable if the drive moves behind a known-good bridge.
  services.fstrim.enable = false;

  # Silent zeroing is the failure mode that bit this host: store paths stayed
  # "valid" in the Nix DB while their contents were 0 bytes, and nothing noticed.
  # A weekly content check turns that into a *failed unit*, which the beszel
  # SystemdFailed alert picks up — the alert path is the point, not the exit code.
  # Idle priority: this reads the whole store and must never compete with the
  # services the box exists to run.
  systemd.services.nix-store-verify = {
    description = "Verify the contents of every path in the Nix store";
    serviceConfig = {
      Type = "oneshot";
      Nice = 19;
      IOSchedulingClass = "idle";
      CPUSchedulingPolicy = "idle";
    };
    script = ''
      set -eu
      ${pkgs.nix}/bin/nix-store --verify --check-contents
    '';
  };
  systemd.timers.nix-store-verify = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 05:30";
      RandomizedDelaySec = "1h";
      # Do not catch up at boot: a clock step would otherwise start it immediately.
      Persistent = false;
    };
  };

  # Under-voltage visibility without vcgencmd. vcgencmd needs
  # /dev/vcio, provided by the bcm2835-vcio driver, which this kernel
  # does not build — CONFIG_BCM2835_VCIO is absent from the pinned LTS
  # config (6.18) and no /dev/vcio exists; the driver lives only in
  # Raspberry Pi's downstream tree, so switching back to mainline would
  # not restore it either. What is built is raspberrypi_hwmon
  # (CONFIG_SENSORS_RASPBERRYPI_HWMON=m, autoloaded), which exposes the
  # live under-voltage alarm at
  # /sys/class/hwmon/hwmon*/in0_lcrit_alarm. Poll it and log at err
  # level so a marginal power supply shows up in the journal instead
  # of silently. Limitation: this is the *current* alarm, not the
  # firmware's sticky "has throttled since boot" bit, so a 5-minute
  # poll can miss a brief dip. It catches sustained under-voltage,
  # which is the failure mode that matters here.
  systemd.services.rpi-voltage-check = {
    description = "Check Raspberry Pi under-voltage alarm";
    serviceConfig.Type = "oneshot";
    # Exit non-zero while the alarm reads 1, rather than only logging. A failed
    # oneshot is what a "Failed Services" alert picks up in Beszel, so a sagging
    # supply reaches a phone instead of waiting in the journal for someone to
    # grep it. The next timer run clears the unit again once the supply recovers.
    script = ''
      tripped=0
      for alarm in /sys/class/hwmon/hwmon*/in0_lcrit_alarm; do
        [ -e "$alarm" ] || continue
        [ "$(cat "$alarm")" = "0" ] || tripped=1
      done
      if [ "$tripped" -ne 0 ]; then
        ${pkgs.util-linux}/bin/logger -p user.err -t rpi-voltage "under-voltage alarm active: supply voltage below threshold"
        exit 1
      fi
    '';
  };
  systemd.timers.rpi-voltage-check = {
    description = "Poll Raspberry Pi under-voltage alarm";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "5m";
      Unit = "rpi-voltage-check.service";
    };
  };
}
