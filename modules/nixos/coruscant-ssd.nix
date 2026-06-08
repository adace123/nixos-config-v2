{
  lib,
  inputs,
  nixos-raspberrypi,
  ...
}:
{
  imports = [
    ./common.nix
    ./home-assistant.nix
    ./disko-ssd.nix
  ];

  # Only apply the overlays we need (bootloader utils + vendor tools),
  # not the kernel/firmware overrides that require GitHub fetches
  nixpkgs.overlays = [
    nixos-raspberrypi.overlays.bootloader
    nixos-raspberrypi.overlays.vendor-pkgs
  ];

  boot.kernelPackages = lib.mkForce inputs.nixpkgs.legacyPackages.aarch64-linux.linuxPackages;

  # Use nixpkgs' firmware (from cache.nixos.org) instead of flake's custom
  # GitHub fetches which trigger HTTP 504 from the Pi's network
  boot.loader.raspberry-pi.firmwarePackage = lib.mkForce inputs.nixpkgs.legacyPackages.aarch64-linux.raspberrypifw;

  networking.hostName = "coruscant";
  networking.useDHCP = true;

  services.avahi = {
    enable = true;
    hostName = "coruscant";
    publish = {
      enable = true;
      workstation = true;
      addresses = true;
      domain = true;
    };
  };

  time.timeZone = "UTC";

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      8123
      1883
      8091
    ];
    allowedUDPPorts = [ 5353 ];
  };
}
