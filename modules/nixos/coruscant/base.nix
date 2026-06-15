{ config, host, ... }:
{
  imports = [
    ../common.nix
    ../beszel.nix
    ./home-assistant
    ./caddy.nix
  ];

  sops.defaultSopsFile = ../../../secrets/default.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.secrets = {
    ts-auth-key = { };
    home-assistant-external-domain = { };
    beszel-domain = { };
  };

  hardware.bluetooth.enable = true;

  networking = {
    hostName = host.hostName;
  };

  services.tailscale = {
    authKeyFile = config.sops.secrets.ts-auth-key.path;
    extraUpFlags = [ "--ssh" ];
  };
}
