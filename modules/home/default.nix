{
  imports = [
    # Shared home-manager settings and user environment.
    ./base.nix
    ./packages.nix
    ./nix.nix
    ./secrets.nix

    # Shell and prompt configuration.
    ./zsh.nix
    ./starship.nix

    # Feature-specific modules.
    ./python.nix
    ./nodejs.nix
    ./git.nix
    ./aerospace.nix
    ./ghostty.nix
    ./fastfetch.nix
    ./ai
    ./zed
    ./1password-agent.nix
    ./nixvim.nix
  ];
}
