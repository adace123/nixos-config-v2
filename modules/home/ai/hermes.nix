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
}
