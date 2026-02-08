{ pkgs, ... }:
{
  imports = [
    ./homebrew.nix
    ./fonts.nix
    ./auto-update.nix
  ];

  # User configuration
  users.users.aaron = {
    name = "aaron";
    home = "/Users/aaron";
  };

  # Nix configuration - Disabled because using Determinate Nix installer
  # Determinate manages its own daemon and conflicts with nix-darwin's Nix management
  nix.enable = false;

  # Note: Configure Nix settings via ~/.config/nix/nix.conf instead
  # To add the llm-agents cache, add to ~/.config/nix/nix.conf:
  #   extra-substituters = https://cache.numtide.com
  #   extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    mas # Mac App Store CLI for homebrew masApps
  ];

  # System configuration
  system = {
    # Set primary user for system defaults
    primaryUser = "aaron";

    # Set Git commit hash for darwin-rebuild
    configurationRevision = null;

    # Used for backwards compatibility
    stateVersion = 4;

    # Keyboard settings
    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = true;
    };

    defaults = {
      # Dock settings
      dock = {
        autohide = true;
        mru-spaces = false;
        minimize-to-application = true;
        show-recents = false;
      };

      # Finder settings
      finder = {
        AppleShowAllExtensions = true;
        ShowPathbar = true;
        FXEnableExtensionChangeWarning = false;
      };

      # NSGlobalDomain settings
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        InitialKeyRepeat = 15;
        KeyRepeat = 2;
        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.trackpad.enableSecondaryClick" = true;
        "com.apple.swipescrolldirection" = false;
      };
    };
  };

  # Shell configuration
  programs.zsh.enable = true;

  # Touch ID for sudo (also enables Apple Watch)
  security.pam.services.sudo_local.touchIdAuth = true;

  # Reattach to user session - fixes Touch ID in tmux/screen
  security.pam.services.sudo_local.reattach = true;

}
