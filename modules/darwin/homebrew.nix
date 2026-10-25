_: {
  # Homebrew configuration
  homebrew = {
    enable = true;

    # Automatically update Homebrew and packages
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      # Remove unlisted packages and casks
      cleanup = "zap";
      # Newer Homebrew requires --force-cleanup to actually apply cleanup (HOMEBREW_ASK
      # no longer works — it exits with code 1 in non-TTY environments)
      extraFlags = [ "--force-cleanup" ];
    };

    # Global settings
    global = {
      brewfile = true;
    };

    # Formulae (command-line packages)
    brews = [
      "awscli" # AWS CLI
      "colima" # Lightweight container runtime
      "gh" # GitHub CLI
      "podman" # Container engine (remote client for coruscant)
      "pam-u2f" # YubiKey PAM module for sudo authentication
      "pre-commit" # Git hooks manager
      "sofka" # Kubernetes TUI, reimagined in Rust (k9s alternative)
      "ykman" # YubiKey Manager CLI
      "terminal-notifier" # macOS notification tool

      # Dependencies for ykman / pam-u2f (must be explicit with cleanup = "zap")
      "cryptography"
      "libcbor"
      "libfido2"

      # Runtime libraries for the manually installed ~/.local/bin/cliamp release
      # binary, which links these by absolute /opt/homebrew path
      "mpg123"
      "flac"
      "libvorbis"
      "libogg"
      "fwdcloudsec/granted/granted" # Granted AWS access
    ];

    taps = [ "fwdcloudsec/granted" ];

    # Casks (GUI applications)
    casks = [
      # Password manager
      "1password"
      "1password-cli"

      # Development
      "antigravity" # Git HTTP server for testing
      "bruno" # API client
      "codex" # OpenAI Codex CLI
      "codex-app" # OpenAI Codex App
      "docker-desktop" # Docker
      "ghostty" # Terminal emulator
      "warp" # AI terminal
      "session-manager-plugin" # AWS SSM
      "ngrok"
      "stablyai/orca/orca"

      # Productivity
      "chatgpt" # OpenAI ChatGPT
      "claude" # Anthropic Claude
      "linear" # Issue tracking
      "raycast" # Spotlight replacement
      "obsidian" # Note-taking
      "handy" # dictation
      "localsend" # file sharing

      # Communication
      "slack"
      "discord"
      "telegram"
      "zoom"
      "whatsapp"
      "microsoft-teams"

      # Utilities
      "balenaetcher" # usb flashing
      "betterdisplay" # Display management

      # Media
      "spotify"
    ];

    # Mac App Store apps (requires mas-cli)
    masApps = {
      # Format: "App Name" = app_id;
      # Find app IDs with: mas search "App Name"
      "Tailscale" = 1475387142;
      "Numbers" = 361304891;
      # App Store name for 1474276998; what `mas search "HP"` returns
      "HP: Print and Support" = 1474276998;
    };
  };
}
