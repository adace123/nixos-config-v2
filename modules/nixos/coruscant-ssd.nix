{ lib, pkgs, ... }: {
  imports = [
    ./common.nix
    ./home-assistant.nix
    ./disko-ssd.nix
  ];

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

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
