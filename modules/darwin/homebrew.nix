_: {
  # Homebrew configuration
  homebrew = {
    enable = true;

    # Automatically update Homebrew and packages
    onActivation = {
      autoUpdate = true;
      upgrade = true;
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
      "pam-u2f" # YubiKey PAM module for sudo authentication
      "pre-commit" # Git hooks manager
      "ykman" # YubiKey Manager CLI
      "terminal-notifier" # macOS notification tool

      # Dependencies for ykman / pam-u2f (must be explicit with cleanup = "zap")
      "cryptography"
      "libcbor"
      "libfido2"
    ];

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
      "cmux"
      "docker-desktop" # Docker
      "ghostty" # Terminal emulator
      "warp" # AI terminal
      "lm-studio" # Local LLMs
      "session-manager-plugin" # AWS SSM
      "ngrok"

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
