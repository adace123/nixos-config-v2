{ lib, pkgs, ... }:
{
  imports = [
    ./base.nix
    ./disko-ssd.nix
  ];

  # Use stock kernel (from cache.nixos.org) instead of vendor RPi kernel
  # to avoid building from source on the Pi
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

  # Ensure /boot/firmware is available during nixos-install for the
  # RPi bootloader installer to copy firmware files (config.txt, DTBs, etc.)
  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-label/FIRMWARE";
    fsType = "vfat";
    options = [ "noatime" ];
    neededForBoot = true;
  };
}
