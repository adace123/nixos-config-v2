{ lib, pkgs, ... }:
{
  imports = [
    ./base.nix
    ./disko-ssd.nix
  ];

  # Use stock kernel (from cache.nixos.org) instead of vendor RPi kernel
  # to avoid building from source on the Pi
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
}
