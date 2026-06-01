{ ... }:

{
  # ── OpNix / 1Password Secrets (Home Manager) ───────────────────
  # Resolves 1Password secrets at build time via OpNix service.
  # Token stored with `sudo opnix token set` (or `just opnix-token-set`).
  programs.onepassword-secrets.enable = true;
}
