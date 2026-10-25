{ host, pkgs, ... }:
{
  imports = [
    ./homebrew.nix
    ./fonts.nix
    ./auto-update.nix
    ./dns.nix
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
        # "Automatically hide and show the menu bar". The OmniWM workspace bar
        # occupies that strip instead — split around the notch, see
        # modules/home/omniwm.nix. Pushing the pointer to the top edge still
        # reveals the real menus.
        _HIHideMenuBar = true;
        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.trackpad.enableSecondaryClick" = true;
        "com.apple.swipescrolldirection" = false;
      };
    };
  };

  # Shell configuration
  programs.zsh.enable = true;

  # Daily: pull main, and only if it moved, build then activate. Commits reach
  # main through a gated Dependabot/CI path, so this agent applies reviewed
  # input bumps instead of hunting for updates itself — it never runs
  # `nix flake update`.
  #
  # Activation needs non-interactive root; without a sudoers rule the agent still
  # builds and notifies, and leaves the switch to `just switch`. See
  # docs/deployment.md#auto-updates.
  services.nix-config-auto-update = {
    enable = true;
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

  # The eight eMudhra/emSign intermediate CAs disclosed on 2026-10-17 had their
  # private keys recoverable from the public certificates, so a forged cert for
  # any domain validates against any trust store that still anchors them
  # (https://emudhra.we-have-a-problem.com/). macOS, Chrome and Firefox block
  # them on their own; this fixes the nix bundle at
  # /etc/ssl/certs/ca-certificates.crt that NIX_SSL_CERT_FILE points at, which
  # otherwise accepted a forged chain for the public checker host.
  #
  # The names are NSS nicknames, which `buildcatrust` matches exactly — the
  # wrapped root is `Comodo AAA Services root`, not `AAA Certificate Services`
  # (that is the certificate's CN, which the blacklist ignores).
  security.pki.caCertificateBlacklist = [
    "Comodo AAA Services root"
    "emSign ECC Root CA - G3"
  ];

}
