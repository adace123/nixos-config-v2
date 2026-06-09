{ lib, pkgs, ... }:
{
  imports = [
    ./base.nix
    ./disko-ssd.nix
  ];

  # Use stock mainline kernel from cache.nixos.org instead of vendor RPi kernel
  # (avoids 30+ min source build — vendor kernel not in binary cache)
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
}
