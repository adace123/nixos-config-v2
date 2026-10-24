{
  pkgs,
  ...
}:
{
  # Boot/kernel settings shared by every Raspberry Pi storage module
  # (ssd.nix, sd.nix). Plain priorities beat the rpi base module's mkDefault
  # ("uboot" bootloader, vendor kernel); the minimal installer (installer.nix)
  # overrides with mkForce where it needs the stock kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader.raspberry-pi = {
    bootloader = "kernel";
    configurationLimit = 2;
  };
  boot.kernelParams = [ "rootwait" ];
  fileSystems."/boot/firmware".neededForBoot = true;
  services.fstrim.enable = true;

  # Under-voltage visibility without vcgencmd: linuxPackages_latest
  # has no bcm2835-vcio driver (no /dev/vcio exists, and the symbol is
  # absent from the kernel config), so vcgencmd cannot work here. The
  # firmware hwmon (raspberrypi_hwmon, already loaded) exposes the
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
    script = ''
      for alarm in /sys/class/hwmon/hwmon*/in0_lcrit_alarm; do
        [ -e "$alarm" ] || exit 0
        if [ "$(cat "$alarm")" != "0" ]; then
          ${pkgs.util-linux}/bin/logger -p user.err -t rpi-voltage "under-voltage alarm active: supply voltage below threshold"
        fi
      done
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
