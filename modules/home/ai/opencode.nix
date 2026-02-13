{
  pkgs,
  inputs,
  ...
}:
let
  shared = import ./shared.nix { inherit inputs pkgs; };
in
{
  programs.opencode = {
    enable = true;
    package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode;

    settings = {
      theme = "catppuccin";
      model = "opencode/minimax-m2.5-free";
      autoupdate = true;
      share = "disabled";
      permission = {
        "*" = "ask";
        read = {
          "*" = "allow";
          "*.env" = "deny";
          "*.env.*" = "deny";
          "*.env.example" = "allow";
        };
        edit = "allow";
        bash = {
          "*" = "ask";
          "git status*" = "allow";
          "git diff*" = "allow";
          "grep*" = "allow";
          "rg*" = "allow";
          "rm*" = "deny";
          "unlink*" = "deny";
          "dd*" = "deny";
        };
        external_directory = {
          "~/Projects/personal/**" = "allow";
        };
      };
    };

    rules = ''
      # General Code Quality Rules

      ## File Loading
      When encountering file references (e.g., @rules/general.md), load them on a need-to-know basis - only when directly relevant to the current task.

      ${shared.rules.code-quality}

      ${shared.rules.best-practices}
    '';

    agents.code-reviewer = shared.agents.code-reviewer.opencode;

    commands.changelog = shared.commands.changelog.opencode;
    commands.commit = shared.commands.commit.opencode;

    inherit (shared) skills;
  };

  programs.zsh.shellAliases = {
    oc = "opencode";
  };
}
