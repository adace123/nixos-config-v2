{
  hostName = "dathomir";
  system = "aarch64-linux";

  # Reports to the beszel hub this host itself runs (see flake-parts/nixos.nix),
  # authenticating with the universal `beszel-token` and the hub SSH public key
  # `beszel-key` in secrets/dathomir.yaml.
  beszelAgent = true;

  sshPublicKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC6DWf0lf4vWTAUmjkulvvZrhCifTS8eFqkDlHPSawrU"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILRSOuLiLN+rY14q+55fd7XUH3rfA54nx3gZJjfmwa7G"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH6NoE7HzOLf05FzjkbsQQkMSbe6AJEm2fgNZeaO6RAe"
  ];
}
