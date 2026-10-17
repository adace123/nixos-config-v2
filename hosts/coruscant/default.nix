{
  hostName = "coruscant";
  system = "aarch64-linux";
  sshPublicKeys = import ../rpi-keys.nix;
  # Off until `beszel-agent-key` (minted by the hub when this system is added
  # there) is in secrets/coruscant.yaml — a declared-but-missing secret fails
  # activation. Flip to true in the same change that adds the key.
  beszelAgent = false;
}
