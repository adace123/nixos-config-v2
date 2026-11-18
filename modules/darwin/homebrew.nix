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
      "gh" # GitHub CLI
      "podman" # Container engine (remote client for coruscant)

      # Container tooling. Kiri.app bundles the docker CLI, Compose and buildx
      # and links them into ~/.kiri/bin; these replace what Docker Desktop used
      # to supply: kubectl, and the credential helpers its config.json names.
      "kubernetes-cli" # kubectl (sofka, kiri k8s)
      "docker-credential-helper" # osxkeychain credsStore for `docker login`
      "docker-credential-helper-ecr" # `ecr-login`, which ~/.docker/config.json names
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

    taps = [
      "fwdcloudsec/granted"
      {
        name = "libracoder/kiri"; # Kiri's cask tap
        trusted = true;
      }
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
      # Kiri — container runtime that speaks the Docker Engine API. Only in its
      # own tap so far (not homebrew-cask yet), hence `trusted`. The cask ships
      # the docker CLI, Compose and buildx inside the app; the app links them
      # into ~/.kiri/bin (see home.sessionPath in modules/home/base.nix). `brew
      # bundle` cannot adopt an existing /Applications/Kiri.app, so a machine
      # that had the DMG installed needs it removed once first.
      {
        name = "libracoder/kiri/kiri";
        trusted = true;
      }
      # Hand-installed; declare it or `cleanup = "zap"` zaps it, and paseo's zap
      # moves files to the Trash, which fails activation without Full Disk Access.
      "paseo" # AI coding agent desktop app
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
      {
        name = "anomalyco/tap/hex";
        trusted = true;
      } # dictation
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
