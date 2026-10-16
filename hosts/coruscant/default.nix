{
  hostName = "coruscant";
  system = "aarch64-linux";
  sshPublicKeys = import ../rpi-keys.nix;
  # Reports to the beszel hub on dathomir; needs its own `beszel-agent-key` in
  # secrets/coruscant.yaml (minted by the hub when the system is added there).
  beszelAgent = true;
}
