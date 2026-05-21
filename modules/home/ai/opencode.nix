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

    tui.theme = "catppuccin";

    settings = {
      model = "opencode/deepseek-v4-flash-free";
      autoupdate = true;
      share = "disabled";
      mcp = {
        context7 = {
          type = "remote";
          url = "https://mcp.context7.com/mcp";
        };
        grep-mcp = {
          type = "remote";
          url = "https://mcp.grep.app";
        };
      };
      permission = {
        "*" = "ask";
        read = {
          "*" = "allow";
          "*.env" = "deny";
          "*.env.*" = "deny";
          "*.env.example" = "allow";
        };
        edit = "allow";
        write = "allow";
        bash = {
          "*" = "ask";
          "git status*" = "allow";
          "git diff*" = "allow";
          "git log*" = "allow";
          "grep*" = "allow";
          "find*" = "allow";
          "ls*" = "allow";
          "rg*" = "allow";
          "rm*" = "deny";
          "unlink*" = "deny";
          "dd*" = "deny";
        };
        glob = "allow";
        grep = "allow";
        webfetch = "allow";
        websearch = "allow";
        question = "allow";
        task = "ask";
        skill = "allow";
        todowrite = "allow";
        lsp = "allow";
        "grep-mcp_searchGitHub" = "allow";
        "terminal-notifier *" = "allow";
        external_directory = {
          "~/Projects/personal/**" = "allow";
        };
      };
    };

    context = ''
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
