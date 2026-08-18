{ config, pkgs, ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # Use XDG config directory for zsh files (modern approach).
    dotDir = "${config.xdg.configHome}/zsh";

    # Advanced completion configuration.
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
      lg = "${pkgs.lazygit}/bin/lazygit";
      update = "nh darwin switch";
      python = "python3";
      cat = "bat";
      ts = "tailscale";
      tf = "tofu";
      assume = "source assume";
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

      # Set blinking bar cursor
      precmd() {
        echo -ne '\e[5 q'
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
}
