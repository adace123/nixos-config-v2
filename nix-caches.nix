# Single source of truth for the binary cache configuration.
# Imported by flake.nix (nixConfig), modules/nixos/common.nix, and
# modules/home/default.nix — add or remove caches here only.
# Key names match nixConfig so flake.nix can import it directly.
{
  extra-substituters = [
    "https://cache.numtide.com"
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
    "https://nixos-raspberrypi.cachix.org"
  ];
  extra-trusted-public-keys = [
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    "nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
  ];
}
