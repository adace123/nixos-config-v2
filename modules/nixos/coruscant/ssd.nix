{ lib, pkgs, ... }:
{
  imports = [
    ./base.nix
    ./disko-ssd.nix
  ];

  # Use stock kernel (from cache.nixos.org) instead of vendor RPi kernel
  # to avoid building from source on the Pi
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

  # Fix U-Boot package name mismatch between nixos-raspberrypi and nixpkgs
  boot.loader.raspberry-pi.ubootPackage = lib.mkForce pkgs.ubootRaspberryPi4_64bit;

  # Fix missing packages from nixos-raspberrypi that aren't in this nixpkgs version
  nixpkgs.overlays = [
    (_: prev: {
      raspberrypi-utils = prev.runCommand "raspberrypi-utils-placeholder" { } "mkdir $out";
    })
  ];

  # Ensure /boot/firmware is mounted early enough for the RPi bootloader
  # installer to copy firmware files (config.txt, DTBs, etc.)
  fileSystems."/boot/firmware".neededForBoot = lib.mkForce true;
}
