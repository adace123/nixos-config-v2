{ config, ... }:
{
  imports = [
    ../common.nix
    ./home-assistant.nix
    ./caddy.nix
  ];

  sops.defaultSopsFile = ../../../secrets/default.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.secrets = {
    ts-auth-key = { };
    home-assistant-external-domain = { };
  };

  hardware.bluetooth.enable = true;

  networking = {
    hostName = "coruscant";
  };

  services.tailscale = {
    authKeyFile = config.sops.secrets.ts-auth-key.path;
    extraUpFlags = [ "--ssh" ];
  };
}
