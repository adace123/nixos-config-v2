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
    firewall.allowedTCPPorts = [ 8123 ]; # Home Assistant Web UI
  };

  services.tailscale = {
    authKeyFile = config.sops.secrets.ts-auth-key.path;
    extraUpFlags = [ "--ssh" ];
  };
}
