{ inputs, ... }:
{
  imports = [
    inputs.nixvim.homeModules.nixvim
    ./nixvim/core.nix
    ./nixvim/plugins.nix
    ./nixvim/keymaps.nix
    ./nixvim/automation.nix
  ];
}
