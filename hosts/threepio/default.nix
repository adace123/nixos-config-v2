{
  hostName = "threepio";
  system = "aarch64-linux";
  sshPublicKeys = import ../rpi-keys.nix;
}
