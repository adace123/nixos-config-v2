{
  imports = [
    # Shared home-manager settings and user environment.
    ./base.nix
    ./macos-defaults.nix
    ./packages.nix
    ./nix.nix
    ./secrets.nix

    # Shell and prompt configuration.
    ./zsh.nix
    ./starship.nix

    # Feature-specific modules.
    ./python.nix
    ./nodejs.nix
    ./ollama.nix
    ./launchd.nix
    ./git.nix
    ./omniwm.nix
    ./ghostty.nix
    ./fastfetch.nix
    ./ai
    ./1password-agent.nix
    ./nixvim.nix
  ];
}
