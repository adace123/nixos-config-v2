{ config, pkgs, ... }:

{
  programs.starship = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      # Minimal prompt with just directory and git
      add_newline = false;

      format = "$directory$git_branch$git_status$nix_shell$character";

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };

      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
        style = "bold cyan";
        format = "[$path]($style) ";
      };

      git_branch = {
        symbol = "";
        style = "bold purple";
        format = "on [$symbol$branch]($style) ";
      };

      git_status = {
        style = "bold red";
        format = "([$all_status$ahead_behind]($style) )";
      };

      nix_shell = {
        symbol = "❄️ ";
        style = "bold blue";
        format = "[$symbol]($style)";
      };

      # Disable everything else
      aws.disabled = true;
      cmd_duration.disabled = true;
      docker_context.disabled = true;
      golang.disabled = true;
      kubernetes.disabled = true;
      nodejs.disabled = true;
      package.disabled = true;
      python.disabled = true;
      rust.disabled = true;
      time.disabled = true;
    };
  };
}
