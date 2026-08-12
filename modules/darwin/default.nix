{ host, pkgs, ... }:
{
  imports = [
    ./homebrew.nix
    ./fonts.nix
    ./auto-update.nix
  ];

  # User configuration
  users.users.${host.user.name} = {
    name = host.user.name;
    home = host.user.homeDirectory;
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
    primaryUser = host.user.name;

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

  # Disabled for now. When re-enabled, the launchd service rebuilds from the
  # flake below and (optionally) auto-switches.
  services.nix-config-auto-update = {
    enable = false;
    darwinConfigName = host.hostName;
  };

  # Touch ID + YubiKey for sudo (also enables Apple Watch).
  # `text` fully overrides nix-darwin's auto-generated lines, so all auth
  # rules are listed explicitly. Fallback order: Touch ID -> YubiKey -> password.
  security.pam.services.sudo_local.text = ''
    # Fixes Touch ID/YubiKey auth in tmux/screen
    auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so
    auth       sufficient     pam_tid.so
    auth       sufficient     /opt/homebrew/lib/pam/pam_u2f.so cue
  '';

}
