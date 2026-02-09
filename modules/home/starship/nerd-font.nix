_:

{
  programs.starship = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      add_newline = true;

      format = "$username$hostname$directory$git_branch$git_status$nix_shell$nodejs$python$rust$golang$docker_context$kubernetes$cmd_duration$line_break$character";

      character = {
        success_symbol = "[](bold green)";
        error_symbol = "[](bold red)";
        vicmd_symbol = "[](bold green)";
      };

      username = {
        format = "[$user]($style)@";
        style_user = "bold yellow";
        show_always = false;
      };

      hostname = {
        format = "[$hostname]($style) ";
        style = "bold yellow";
        ssh_only = true;
      };

      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
        style = "bold cyan";
        format = "[$path]($style)[$read_only]($read_only_style) ";
        read_only = " ";
      };

      git_branch = {
        symbol = " ";
        style = "bold purple";
        format = "on [$symbol$branch(:$remote_branch)]($style) ";
      };

      git_status = {
        style = "bold red";
        ahead = "⇡\${count}";
        behind = "⇣\${count}";
        diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
        conflicted = "🏳";
        deleted = "✘";
        renamed = "»";
        modified = "✱";
        staged = "[++\($count\)](green)";
        untracked = "…";
        format = "([$all_status$ahead_behind]($style) )";
      };

      nix_shell = {
        symbol = " ";
        style = "bold blue";
        format = "via [$symbol$state( \\($name\\))]($style) ";
        impure_msg = "[impure](bold red)";
        pure_msg = "[pure](bold green)";
      };

      nodejs = {
        symbol = " ";
        style = "bold green";
        format = "via [$symbol($version )]($style)";
      };

      python = {
        symbol = " ";
        style = "bold yellow";
        format = "via [$symbol$pyenv_prefix($version )( \\($virtualenv\\) )]($style)";
      };

      rust = {
        symbol = " ";
        style = "bold red";
        format = "via [$symbol($version )]($style)";
      };

      golang = {
        symbol = " ";
        style = "bold cyan";
        format = "via [$symbol($version )]($style)";
      };

      java = {
        symbol = " ";
        style = "bold red";
        format = "via [$symbol($version )]($style)";
      };

      ruby = {
        symbol = " ";
        style = "bold red";
        format = "via [$symbol($version )]($style)";
      };

      php = {
        symbol = " ";
        style = "bold purple";
        format = "via [$symbol($version )]($style)";
      };

      docker_context = {
        symbol = " ";
        style = "bold blue";
        format = "via [$symbol$context]($style) ";
        only_with_files = true;
      };

      kubernetes = {
        symbol = "☸ ";
        style = "bold blue";
        format = "on [$symbol$context( \\($namespace\\))]($style) ";
        disabled = false;
      };

      aws = {
        symbol = " ";
        style = "bold yellow";
        format = "on [$symbol($profile )( \\($region\\) )]($style)";
      };

      gcloud = {
        symbol = "☁️ ";
        style = "bold blue";
        format = "on [$symbol$account(@$domain)( \\($region\\))]($style) ";
      };

      terraform = {
        symbol = "💠 ";
        style = "bold purple";
        format = "via [$symbol$workspace]($style) ";
      };

      package = {
        symbol = " ";
        style = "bold 208";
        format = "is [$symbol$version]($style) ";
      };

      cmd_duration = {
        min_time = 500;
        format = "took [$duration](bold yellow) ";
        show_milliseconds = false;
      };

      time = {
        disabled = false;
        format = "🕙[$time]($style) ";
        style = "bold white";
        time_format = "%T";
      };

      memory_usage = {
        disabled = false;
        threshold = 75;
        symbol = " ";
        style = "bold dimmed white";
        format = "via $symbol[$ram( | $swap)]($style) ";
      };

      battery = {
        full_symbol = " ";
        charging_symbol = " ";
        discharging_symbol = " ";
        unknown_symbol = " ";
        empty_symbol = " ";
      };
    };
  };
}
