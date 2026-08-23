{ config, host, ... }:
{
  imports = [
    ./common.nix
    ./beszel.nix
    ./home-assistant
    ./caddy.nix
    ./podman.nix
  ];

  # Per-host secrets file — each host only decrypts its own secrets
  # (see .sops.yaml creation rules).
  sops.defaultSopsFile = ../../secrets/${host.hostName}.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.secrets = {
    ts-auth-key = { };
    home-assistant-external-domain = { };
    beszel-domain = { };
    alexa-notify-me-api-key = { };
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
