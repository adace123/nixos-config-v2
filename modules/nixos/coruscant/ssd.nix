{ lib, pkgs, ... }:
{
  imports = [
    ./base.nix
    ./disko-ssd.nix
  ];

  # Use stock kernel (from cache.nixos.org) instead of vendor RPi kernel
  # to avoid building from source on the Pi
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

  # Ensure /boot/firmware is mounted early enough for the RPi bootloader
  # installer to copy firmware files (config.txt, DTBs, etc.)
  fileSystems."/boot/firmware".neededForBoot = lib.mkForce true;
}
