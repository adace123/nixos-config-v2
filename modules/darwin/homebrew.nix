{ config, pkgs, ... }:

{
  # Homebrew configuration
  homebrew = {
    enable = true;

    # Automatically update Homebrew and packages
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      # Remove unlisted packages and casks
      cleanup = "zap";
    };

    # Global settings
    global = {
      brewfile = true;
    };

    # Taps (additional repositories)
    taps = [
      "nikitabobko/tap" # AeroSpace window manager
    ];

    # Formulae (command-line packages)
    brews = [
      "awscli"
      "colima"
      "gh"
      "pam-u2f" # YubiKey PAM module for sudo authentication
      "pre-commit"
      "ykman" # YubiKey Manager CLI
    ];

    # Casks (GUI applications)
    casks = [
      # Password manager
      "1password"
      "1password-cli"

      # Browsers
      # "firefox"
      # "google-chrome"

      # Development
      "claude-code"
      "codex-app"
      "docker-desktop"
      "ghostty"
      "zed@preview"
      "warp"

      # Productivity
      "nikitabobko/tap/aerospace" # Tiling window manager
      "chatgpt"
      "claude"
      "raycast" # Spotlight replacement
      "obsidian" # Note-taking

      # Communication
      "slack"
      "discord"
      "zoom"
      "whatsapp"
      "microsoft-teams"

      # Utilities
      "balenaetcher" # usb flashing
      "betterdisplay"
    ];

    # Mac App Store apps (requires mas-cli)
    masApps = {
      # Format: "App Name" = app_id;
      # Find app IDs with: mas search "App Name"
      # Example:
      "Tailscale" = 1475387142;
    };
  };
}
