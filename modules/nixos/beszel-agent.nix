{
  config,
  ...
}:
{
  # Beszel agent, authenticating with a *universal token* rather than the
  # per-system `KEY` that the hub's "Add system" flow hands out.
  #
  # Why: with TOKEN + HUB_URL the agent makes an outgoing WebSocket connection to
  # the hub, so nothing needs to reach the agent (no inbound 45876, no firewall
  # exemption) and the hub needs no per-system key — which means provisioning an
  # agent is one shared secret and a deploy, not a click in the hub UI followed by
  # copying a unique key into that host's secrets. Create the token once at
  # /settings/tokens and put the same value in each host's file below; it can also
  # be created through the hub's PocketBase API with a superuser token.
  #
  # Add `beszel-token` to the host's file in secrets/ BEFORE deploying: this
  # template renders it, and a missing value fails activation.
  sops.secrets.beszel-token = { };
  # The hub's public name, already in this host's secrets, is the URL the agent
  # dials. dathomir could short-circuit to 127.0.0.1:8090, but going through the
  # name is what every other host has to do, and keeps one code path.
  sops.secrets.beszel-domain = { };

  sops.templates."beszel-agent-env" = {
    content = ''
      TOKEN=${config.sops.placeholder.beszel-token}
      HUB_URL=https://${config.sops.placeholder.beszel-domain}
    '';
    owner = "beszel-agent";
    group = "beszel-agent";
    mode = "0400";
  };

  services.beszel.agent = {
    enable = true;
    environmentFile = config.sops.templates."beszel-agent-env".path;
  };
}
