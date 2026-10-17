{
  hostName = "coruscant";
  system = "aarch64-linux";
  sshPublicKeys = import ../rpi-keys.nix;
  # Reports to the beszel hub on dathomir, authenticating with the universal
  # `beszel-token` in secrets/coruscant.yaml.
  beszelAgent = true;
}
