{ ... }:

{
  # ── Hermes config.yaml ──────────────────────────────────────────
  # Managed via Nix — do NOT use `hermes config set KEY VAL` or
  # the atomic-replace will fail (symlinked to nix store).
  home.file.".hermes/config.yaml".text = builtins.toJSON {
    model = {
      default = "deepseek-v4-flash-free";
      provider = "opencode-zen";
    };
    terminal = {
      backend = "local";
      persistent_shell = true;
    };
    memory = {
      memory_enabled = true;
      provider = "holographic";
    };
    approvals.mode = "manual";
    compression.enabled = true;
    toolsets = [ "all" ];
  };

  # ── Hermes .env secrets (via OpNix / 1Password) ─────────────────
  # API keys and credentials for Hermes web search, providers, etc.
  # Actual values resolved from 1Password at build time by OpNix.
  # Manually editable after deploy — writes a real file, not a
  # nix-store symlink.
  programs.onepassword-secrets.secrets = {
    opencodeApiKey = {
      name = "OPENCODE_ZEN_API_KEY";
      reference = "op://Personal/Development/Opencode API Key";
      path = ".hermes/.env";
      mode = "0600";
    };
  };
}
