{ ... }:
{
  programs.starship = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      # Minimal prompt below the solid bar
      format = "$directory$fill$git_branch$git_status$nix_shell$cmd_duration$line_break$character";

      add_newline = false;

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

      # Character (blinking bar added via precmd)
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
}
