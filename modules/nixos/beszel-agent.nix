{
  config,
  ...
}:
{
  # Beszel agent, dialling the hub over an outgoing WebSocket with a *universal
  # token* rather than waiting for the hub to dial it over inbound SSH.
  #
  # The agent needs three values. TOKEN is the universal token, created once at
  # the hub's /settings/tokens (the same value on every agent; it can also be
  # created through the hub's PocketBase API with a superuser token). HUB_URL is
  # the hub's public name, already in this host's secrets. KEY is the hub's SSH
  # *public* key, which the agent uses to verify the hub's auth-challenge
  # signature — the 0.20.0 agent refuses to start without it even in token mode.
  # The hub keeps one global ed25519 keypair at
  # /var/lib/beszel-hub/beszel_data/id_ed25519, so every agent uses the same KEY;
  # derive it with `ssh-keygen -y -f` on the hub host. (It is public, but lives
  # in sops alongside the token to keep one mechanism for agent credentials.)
  #
  # Add `beszel-token` and `beszel-key` to the host's file in secrets/ BEFORE
  # deploying: this template renders them, and a missing value fails activation.
  sops.secrets.beszel-token = { };
  sops.secrets.beszel-key = { };
  # The hub's public name, already in this host's secrets, is the URL the agent
  # dials. dathomir could short-circuit to 127.0.0.1:8090, but going through the
  # name is what every other host has to do, and keeps one code path.
  sops.secrets.beszel-domain = { };

  sops.templates."beszel-agent-env" = {
    content = ''
      TOKEN=${config.sops.placeholder.beszel-token}
      HUB_URL=https://${config.sops.placeholder.beszel-domain}
      KEY=${config.sops.placeholder.beszel-key}
    '';
    owner = "beszel-agent";
    group = "beszel-agent";
    mode = "0400";
  };

  services.beszel.agent = {
    enable = true;
    environmentFile = config.sops.templates."beszel-agent-env".path;
  };

  # The agent serves each monitored service's journal (last 200 lines) to the
  # hub UI, and reads it with journalctl — which needs journal access. Without
  # this the services list still shows but the logs panel is hidden. The agent
  # checks access at startup, so a restart picks up permission changes.
  systemd.services.beszel-agent.serviceConfig.SupplementaryGroups = [ "systemd-journal" ];
}
