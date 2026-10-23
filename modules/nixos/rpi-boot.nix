{
  pkgs,
  ...
}:
{
  # Boot/kernel settings shared by every Raspberry Pi storage module
  # (ssd.nix, sd.nix).
  #
  # Pinned to the LTS kernel rather than linuxPackages_latest. coruscant hard-hung
  # with no panic, OOM, under-voltage event or I/O error in its journal on the
  # first boot after a deploy that moved linuxPackages_latest from 7.1.8 to
  # 7.2.2, and the two boots after that failed to stay up past 30-90s. Mainline
  # instability on the Pi 4 (BCM2711) is the prime suspect; 6.18 LTS has none of
  # that history. Revisit once a later mainline has run clean for a while.
  # Analysis: .pi/plans/coruscant-unresponsive-diagnosis.md
  boot.kernelPackages = pkgs.linuxPackages;

  # The Pi 4 has no RTC, and nothing enabled a watchdog, so a frozen kernel
  # stayed frozen until someone pulled the power. bcm2835_wdt is probed on every
  # boot (it appears in the journal as bcm2835-wdt/bcm2835-pm), so let systemd
  # drive it: if the manager stops petting the device, the board reboots itself
  # instead of hanging silently.
  #
  # RebootWatchdogSec is deliberately NOT set: bcm2835_wdt cannot hold a long
  # timeout, so a large value is silently ignored, and a short one (the hardware
  # tops out around 15 s) would hard-reset the board in the middle of a shutdown
  # while podman is still stopping Home Assistant. The runtime watchdog plus the
  # canary below are what actually cover the failures seen here.
  systemd.settings.Manager.RuntimeWatchdogSec = "10s";

  # Kernel-side insurance for the USB root device. On 2026-10-23 coruscant lost
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
    configurationLimit = 2;
  };
  fileSystems."/boot/firmware".neededForBoot = true;
  services.fstrim.enable = true;
}
