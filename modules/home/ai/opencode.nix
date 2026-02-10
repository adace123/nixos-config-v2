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
      autoupdate = true;
      autoshare = false;
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

    skills = shared.skills;
  };

  programs.zsh.shellAliases = {
    oc = "opencode";
  };
}
