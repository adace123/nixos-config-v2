{ ... }:

{
  # ── Hermes config.yaml ──────────────────────────────────────────
  # Managed via Nix — do NOT use `hermes config set KEY VAL` or
  # the atomic-replace will fail (symlinked to nix store).
  #
  # Note: if hermes ever does atomic-replace the symlink (or you edit
  # the file manually), it leaves a read-only config.yaml.bak (0444).
  # `home-manager.overwriteBackup` (flake-parts/darwin.nix) makes home-manager
  # rm the stale .bak before backing up, so the read-only mode never triggers
  # an interactive `mv` prompt (which would hang activation).
  home.file.".hermes/config.yaml" = {
    force = true;
    text = builtins.toJSON {
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
  };
}
