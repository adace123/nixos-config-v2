{ config, host, ... }:
{
  # sops-nix home-manager: decrypt this host's secrets with its per-host age
  # key. The private key lives at ~/.config/sops/age/keys.txt and matches the
  # host recipient in .sops.yaml; secrets are read from secrets/<host>.yaml.
  sops.defaultSopsFile = ../../secrets/${host.hostName}.yaml;
  sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
}
