{ lib, pkgs, ... }:
{
  imports = [
    ./base.nix
    ./disko-ssd.nix
  ];

  # Use stock mainline kernel from cache.nixos.org instead of vendor RPi kernel
  # (avoids 30+ min source build — vendor kernel not in binary cache)
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
  boot.loader.raspberry-pi.bootloader = "kernel";
  boot.initrd.availableKernelModules = [
    "uas"
    "usb_storage"
    "sd_mod"
    "scsi_mod"
  ];
  boot.kernelParams = [ "rootwait" ];

  fileSystems."/boot/firmware".neededForBoot = true;
  systemd.tmpfiles.rules = [ "d /boot/firmware 0755 root root -" ];
  system.activationScripts.mountBootFirmware = lib.stringAfter [ "specialfs" ] ''
    mkdir -p /boot/firmware
    if ! ${pkgs.util-linux}/bin/findmnt --mountpoint /boot/firmware >/dev/null; then
      ${pkgs.util-linux}/bin/mount /boot/firmware
    fi
  '';
}
