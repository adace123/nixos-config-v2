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
    };

    # Global settings
    global = {
      brewfile = true;
    };

    # Taps (additional repositories)
    taps = [
      "nikitabobko/tap" # AeroSpace window manager
      "common-fate/granted" # AWS Granted
    ];

    # Formulae (command-line packages)
    brews = [
      "awscli" # AWS CLI
      "colima" # Lightweight container runtime
      "gh" # GitHub CLI
      "pam-u2f" # YubiKey PAM module for sudo authentication
      "pre-commit" # Git hooks manager
      "ykman" # YubiKey Manager CLI
      "common-fate/granted/granted" # AWS credentials manager
      "terminal-notifier" # macOS notification tool
    ];

    # Casks (GUI applications)
    casks = [
      # Password manager
      "1password"
      "1password-cli"

      # Development
      "antigravity" # Git HTTP server for testing
      "bruno" # API client
      "codex-app" # OpenAI Codex
      "cmux" # Claude Code CLI
      "docker-desktop" # Docker
      "ghostty" # Terminal emulator
      "warp" # AI terminal
      "lm-studio" # Local LLMs
      "yaak@beta" # API client
      "session-manager-plugin" # AWS SSM

      # Productivity
      "nikitabobko/tap/aerospace" # Tiling window manager
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
