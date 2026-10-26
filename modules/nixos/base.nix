{
  config,
  host,
  lib,
  ...
}:
{
  imports = [
    ./common.nix
    ./home-assistant
    ./caddy.nix
    ./podman.nix
  ]
  # The beszel hub now lives on dathomir, so these hosts run the *agent* instead —
  # only where the host opts in, because each agent needs its own key in that
  # host's secrets file and a missing one fails activation.
  ++ lib.optional (host.beszelAgent or false) ./beszel-agent.nix;

  # Per-host secrets file — each host only decrypts its own secrets
  # (see .sops.yaml creation rules).
  sops.defaultSopsFile = ../../secrets/${host.hostName}.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.secrets = {
    ts-auth-key = { };
    home-assistant-external-domain = { };
    alexa-notify-me-api-key = { };
    # Pocket ID OIDC for Home Assistant (hass-oidc-auth public client).
    # oidc-client-id is filled in after creating the client in Pocket ID
    # (see docs); discovery URL is the Pocket ID well-known endpoint.
    oidc-client-id = { };
    oidc-discovery-url = { };
  };

  hardware.bluetooth.enable = true;

  networking = {
    inherit (host) hostName;
  };

  services.tailscale = {
    authKeyFile = config.sops.secrets.ts-auth-key.path;
    extraUpFlags = [ "--ssh" ];
  };
}
