{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./common.nix
    ./home-assistant.nix
    ./disko-ssd.nix
  ];

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

  # Use nixpkgs' firmware packages (from cache.nixos.org) instead of
  # nixos-raspberrypi flake's custom GitHub versions which trigger HTTP 504
  nixpkgs.overlays = [
    (_: _: {
      raspberrypifw = inputs.nixpkgs.legacyPackages.aarch64-linux.raspberrypifw;
      firmwareLinuxNonfree = inputs.nixpkgs.legacyPackages.aarch64-linux.firmwareLinuxNonfree;
      raspberrypiWirelessFirmware =
        inputs.nixpkgs.legacyPackages.aarch64-linux.raspberrypiWirelessFirmware;
    })
  ];

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
