{ pkgs, ... }:
{
  # Extra packages needed for plugins
  programs.nvf.settings.vim.extraPackages = with pkgs; [
    lazygit
    yazi # File manager
    ruff # Python linter/formatter
    basedpyright # Python type checker
    nixd # Nix language server
    deadnix # Nix dead code remover
    statix # Nix linter and formatter
  ];
}
