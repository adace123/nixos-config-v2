{
  config,
  ...
}:
{
  # Beszel agent. The hub polls each agent on port 45876 and authenticates with a
  # key that the hub mints when you add that system in its UI — so the value is a
  # secret, and it reaches the agent as an env file rather than through the Nix
  # store.
  #
  # Add `beszel-agent-key` to the host's file in secrets/ BEFORE deploying: this
  # template renders it, and a missing value fails activation. The key is per
  # system, so each host that runs an agent needs its own.
  sops.secrets.beszel-agent-key = { };

  sops.templates."beszel-agent-env" = {
    content = ''
      KEY=${config.sops.placeholder.beszel-agent-key}
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
