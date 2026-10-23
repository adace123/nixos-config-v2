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
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "10s";
    RebootWatchdogSec = "2min";
  };

  boot.loader.raspberry-pi = {
    bootloader = "kernel";
    configurationLimit = 2;
  };
  boot.kernelParams = [ "rootwait" ];
  fileSystems."/boot/firmware".neededForBoot = true;
  services.fstrim.enable = true;
}
