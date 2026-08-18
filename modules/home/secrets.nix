{ config, ... }:
{
  # sops-nix home-manager: decrypt secrets (e.g. tinyfish-api-key) with the
  # standard sops age key. Matches the age recipient in secrets/default.yaml.
  sops.defaultSopsFile = ../../secrets/default.yaml;
  sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
}
