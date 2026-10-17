{
  hostName = "coruscant";
  system = "aarch64-linux";
  sshPublicKeys = import ../rpi-keys.nix;
  # Off until `beszel-token` (a universal token, created once at the hub's
  # /settings/tokens) is in secrets/coruscant.yaml — a declared-but-missing secret
  # fails activation. Flip to true in the same change that adds the token.
  beszelAgent = false;
}
