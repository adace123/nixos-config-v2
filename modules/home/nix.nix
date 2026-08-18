{ lib, ... }:
let
  caches = import ../../nix-caches.nix;
in
{
  # Written to ~/.config/nix/nix.conf since nix-darwin has nix.enable = false
  # (using Determinate Nix installer instead).
  # Single source of truth: nix-caches.nix (also used by flake.nix `nixConfig`
  # and modules/nixos/common.nix).
  xdg.configFile."nix/nix.conf".text = ''
    experimental-features = nix-command flakes
    max-jobs = auto
    cores = 0
    extra-substituters = ${lib.concatStringsSep " " caches.extra-substituters}
    extra-trusted-public-keys = ${lib.concatStringsSep " " caches.extra-trusted-public-keys}
  '';
}
