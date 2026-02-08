{
  inputs,
  ...
}:
{
  # Import nvf home-manager module
  imports = [
    inputs.nvf.homeManagerModules.default

    # Import all submodules
    # plugins.nix must be first since it exports customPlugins
    ./plugins.nix
    ./packages.nix
    ./core-settings.nix
    ./completion.nix
    ./ui.nix
    ./keybindings.nix
    ./lua-config.nix
    ./extra-plugins.nix
  ];

  # Enable nvf
  programs.nvf.enable = true;

  # Shell aliases
  programs.zsh.shellAliases = {
    v = "nvim";
    vi = "nvim";
    vim = "nvim";
    nvim-clean = ''nvim --cmd "lua require('persistence').stop()"'';
  };
}
