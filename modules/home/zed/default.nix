{ pkgs, ... }:
{
  imports = [
    ./settings.nix
    ./keybindings.nix
    ./tasks.nix
  ];

  programs.zed-editor = {
    enable = false;

    extraPackages = with pkgs; [
      nixd
      nil
      nixfmt
      nodejs
      ruff
    ];
  };

  programs.zed-editor-extensions = {
    enable = true;
    packages = with pkgs.zed-extensions; [
      nix
      toml
      git-firefly
      catppuccin
      catppuccin-icons
      just
    ];
  };

  programs.zsh.shellAliases = {
    zed = "zeditor";
  };
}
