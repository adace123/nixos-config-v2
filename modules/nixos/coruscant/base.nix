{ config, ... }:
{
  imports = [
    ../common.nix
    ./home-assistant.nix
  ];

  sops.defaultSopsFile = ../../../secrets/default.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.secrets.ts-auth-key = { };

  networking = {
    hostName = "coruscant";
    useDHCP = true;

    firewall = {
      enable = true;
      trustedInterfaces = [ "tailscale0" ];
      allowedTCPPorts = [
        8123 # Home Assistant Web UI
      ];
      allowedUDPPorts = [ 5353 ]; # mDNS
    };
  };

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

  services.tailscale = {
    authKeyFile = config.sops.secrets.ts-auth-key.path;
    extraUpFlags = [ "--ssh" ];
  };

  time.timeZone = "UTC";
}
