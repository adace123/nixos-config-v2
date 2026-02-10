{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./python.nix
    ./nodejs.nix
    ./git.nix
    ./aerospace.nix
    ./ghostty.nix
    ./fastfetch.nix
    ./nvf
    ./zellij.nix
    ./ai
  ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home = {
    # This value determines the Home Manager release that your configuration is
    # compatible with. This helps avoid breakage when a new Home Manager release
    # introduces backwards incompatible changes.
    stateVersion = "24.05";

    # Packages to install for this user
    packages = with pkgs; [
      # Development tools
      ripgrep
      fd
      gum
      jq
      htop
      btop # Better htop with more features
      k9s # Kubernetes CLI manager
      kubectx
      yazi # Modern terminal file manager
      tree
      direnv # Automatic environment loading
      just # Command runner
      zoxide # Smart directory jumping
      glab
      nh # Nix helper for better rebuild/clean/search UX

      # Modern CLI replacements
      bat # cat replacement
      eza # ls replacement
      fzf # fuzzy finder
      gum # Beautiful terminal UI components

      # Zsh completions
      carapace # Multi-shell completion generator (aws, gh, kubectl, docker, etc.)
      nix-zsh-completions # Completions for Nix commands
      zsh-completions # Additional completion definitions

      # Zsh plugins
      zsh-autopair # Auto-close and delete matching delimiters
    ];

    # Environment variables
    sessionVariables = {
      DIRENV_LOG_FORMAT = ""; # Hide direnv export output
      EDITOR = "nvim";
      NH_FLAKE = "${config.home.homeDirectory}/Projects/nixos-config-v2"; # Enable nh commands without specifying flake path
    };
  };

  # AI Assistant Selector Script
  home.file.".local/bin/ai-selector" = {
    source = ../../scripts/ai-selector.sh;
    executable = true;
  };

  # Nix configuration for Determinate Nix
  home.file.".config/nix/nix.conf".text = ''
    # Flakes support (if not already enabled by Determinate)
    experimental-features = nix-command flakes

    # Binary caches
    extra-substituters = https://cache.numtide.com
    extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=

    # Performance
    max-jobs = auto
    cores = 0
  '';

  # Programs configuration
  programs = {
    # Zsh configuration
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      # Use XDG config directory for zsh files (modern approach)
      dotDir = "${config.xdg.configHome}/zsh";

      # Advanced completion configuration
      completionInit = ''
        # Load and initialize the completion system
        autoload -Uz compinit
        compinit

        # Case insensitive completion
        zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

        # Color completion for files and directories
        zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"

        # Complete . and .. special directories
        zstyle ':completion:*' special-dirs true

        # Group results by category
        zstyle ':completion:*' group-name '''

        # Enable menu selection for completions
        zstyle ':completion:*:*:*:*:*' menu select

        # Verbose completion
        zstyle ':completion:*' verbose yes

        # Descriptions for completion categories
        zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
        zstyle ':completion:*:messages' format '%F{purple}-- %d --%f'
        zstyle ':completion:*:warnings' format '%F{red}-- no matches found --%f'
        zstyle ':completion:*:corrections' format '%F{green}-- %d (errors: %e) --%f'

        # Use cache for completions
        zstyle ':completion:*' use-cache on
        zstyle ':completion:*' cache-path "$HOME/.zsh/cache"

        # Complete options for commands
        zstyle ':completion:*' complete-options true

        # Process completion
        zstyle ':completion:*:*:*:*:processes' command "ps -u $USER -o pid,user,comm -w -w"
        zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'

        # Completion for common commands
        zstyle ':completion:*:git-checkout:*' sort false
        zstyle ':completion:*' file-sort modification

        # Don't complete uninteresting files
        zstyle ':completion:*:*:*:*:*' file-patterns '^*.(o|pyc|pyo|so|class):source-files' '*:all-files'
      '';

      shellAliases = {
        ll = "ls -la";
        ls = "${pkgs.eza}/bin/eza --color=always --icons=always";
        update = "nh darwin switch";
        python = "python3"; # Use ipython as default
        py = "ipython";
        cat = "bat";
        gemini = "bunx -y @google/gemini-cli";
        opencode = "bunx -y opencode-ai";
        copilot = "bunx -y @github/copilot";
        ts = "tailscale";
        # Note: zoxide commands available:
        # - 'z <query>' - Jump to directory (with tab completion)
        # - 'zi' or 'cdi' - Interactive directory picker with fzf
      };

      initContent = ''
        # Add completion paths
        fpath=($HOME/.nix-profile/share/zsh/site-functions $HOME/.nix-profile/share/zsh/$ZSH_VERSION/functions $HOME/.nix-profile/share/zsh/vendor-completions $fpath)

        # Zsh autopair - auto-close quotes, brackets, and angle brackets
        source ${pkgs.zsh-autopair}/share/zsh/zsh-autopair/autopair.zsh
        autopair-init

        # Add ~/.local/bin to PATH
        export PATH="$HOME/.local/bin:$PATH"

        # Homebrew PATH initialization
        if [[ -f "/opt/homebrew/bin/brew" ]]; then
          eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -f "/usr/local/bin/brew" ]]; then
          eval "$(/usr/local/bin/brew shellenv)"
        fi

        if [[ -f "~/.config/op/plugins.sh" ]]; then
          source ~/.config/op/plugins.sh
        fi

        # Direnv integration
        eval "$(direnv hook zsh)"

        # Zoxide integration with fzf for interactive selection
        # This enables tab completion for 'z' command and 'zi' for interactive fzf picker
        eval "$(zoxide init zsh)"

        # Add 'cdi' as an alias for interactive directory selection with fzf
        alias cdi='zi'

        # FZF key bindings and completion
        if command -v fzf-share >/dev/null; then
          source "$(fzf-share)/key-bindings.zsh"
          source "$(fzf-share)/completion.zsh"
        fi

        # Carapace completion (handles aws, gh, kubectl, docker, terraform, and 800+ more commands)
        if command -v carapace >/dev/null; then
          export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense' # Enable completion bridges
          zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
          source <(carapace _carapace)
        fi

        # Function to reset cursor on each prompt
        precmd() {
          echo -ne '\e[6 q'
        }

        # Run fastfetch on new terminal
        if [[ -o interactive ]] && [[ -z "$TMUX" ]] && [[ -z "$FASTFETCH_RAN" ]]; then
          export FASTFETCH_RAN=1
          fastfetch --config ~/.config/fastfetch/config.jsonc
        fi
      '';

      oh-my-zsh = {
        enable = true;
        theme = ""; # Disable theme to use starship
        plugins = [
          # Git
          "git"

          # Utilities
          "sudo" # Press ESC twice to add sudo
          "command-not-found" # Suggests packages when command not found
          "extract" # Smart archive extraction with 'x <file>'
          "copypath" # Copy current path to clipboard
          "copyfile" # Copy file contents to clipboard
          "copybuffer" # Copy command line buffer to clipboard
          "colored-man-pages" # Colorize man pages

          # Development
          "docker"
          "kubectl"
          "npm"
          "pip"
          "python"

          # Web & Search
          "jsontools" # JSON pretty printing (pp_json, is_json, etc)
          "web-search" # Search from terminal (google, stackoverflow, github)

          # Completion enhancements
          "zsh-interactive-cd" # Interactive completion for cd

          # macOS specific
          "macos" # macOS specific commands
        ];
      };
    };

    # Starship prompt - Clean and modern
    starship = {
      enable = true;
      enableZshIntegration = true;

      settings = {
        # Use a preset for consistency
        format = "$username$hostname$directory$git_branch$git_status$nix_shell$fill$cmd_duration$line_break$character";

        add_newline = true;

        # Username
        username = {
          style_user = "bold blue";
          style_root = "bold red";
          format = "[$user]($style) ";
          show_always = false;
        };

        # Hostname
        hostname = {
          ssh_only = true;
          format = "on [$hostname](bold yellow) ";
          disabled = false;
        };

        # Directory
        directory = {
          style = "bold cyan";
          truncation_length = 3;
          truncate_to_repo = true;
          read_only = " 󰌾";
        };

        # Git
        git_branch = {
          symbol = " ";
          style = "bold purple";
        };

        git_status = {
          ahead = "⇡$count";
          diverged = "⇕⇡$ahead_count⇣$behind_count";
          behind = "⇣$count";
          conflicted = "🏳";
          untracked = "?";
          stashed = "📦";
          modified = "!";
          staged = "+$count";
          renamed = "»";
          deleted = "✘";
          style = "bold red";
        };

        # Character
        character = {
          success_symbol = "[⚛](bold green)";
          error_symbol = "[⚛](bold red)";
          vicmd_symbol = "[⚛](bold green)";
        };

        # Fill space between left and right
        fill = {
          symbol = " ";
        };

        # Command duration
        cmd_duration = {
          min_time = 2000;
          format = "[$duration](bold yellow)";
          show_milliseconds = false;
        };

        # Language versions (only show when in project)
        nodejs = {
          symbol = " ";
          format = "[$symbol($version)]($style) ";
          detect_files = [
            "package.json"
            ".node-version"
            ".nvmrc"
          ];
          detect_folders = [ "node_modules" ];
        };

        python = {
          symbol = " ";
          format = "[$symbol($version)]($style) ";
          detect_extensions = [ "py" ];
          detect_files = [
            "requirements.txt"
            ".python-version"
            "pyproject.toml"
            "Pipfile"
          ];
        };

        rust = {
          symbol = " ";
          format = "[$symbol($version)]($style) ";
          detect_extensions = [ "rs" ];
          detect_files = [ "Cargo.toml" ];
        };

        bun = {
          symbol = "🥟 ";
          format = "[$symbol($version)]($style) ";
        };

        # Nix shell
        nix_shell = {
          symbol = " ";
          style = "bold blue";
          format = "via [$symbol$state( \($name\))]($style) ";
          impure_msg = "[impure](bold yellow)";
          pure_msg = "[pure](bold green)";
          heuristic = true;
        };

        # Disable time by default
        time = {
          disabled = true;
        };

        # Disable less common languages
        aws.disabled = true;
        gcloud.disabled = true;
        kubernetes.disabled = true;
        docker_context.disabled = true;
      };
    };

    # Let Home Manager install and manage itself
    home-manager.enable = true;
  };

  xdg.enable = true;
}
