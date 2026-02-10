{
  config,
  pkgs,
  inputs,
  ...
}:
let
  shared = import ./shared.nix { inherit inputs pkgs; };
in
{
  programs.claude-code = {
    enable = true;
    package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;

    settings = {
      theme = "dark";
      statusLine = {
        type = "command";
        command = "bash -c 'basename $(dirname $(pwd))/$(basename $(pwd)); git branch --show-current 2>/dev/null | xargs -I{} echo \" ({})\" || true; echo -n \" | \"; npx ccusage@latest statusline' | tr -d '\\n'";
      };
      permissions = {
        allow = [
          "Bash(git diff*)"
          "Bash(git status*)"
          "Bash(git log*)"
          "Bash(git show*)"
          "Bash(git branch*)"
          "Bash(git checkout*)"
          "Bash(git switch*)"
          "Bash(git stash*)"
          "Bash(git restore*)"
          "Bash(git add*)"
          "Bash(cat *)"
          "Bash(ls *)"
          "Bash(grep *)"
          "Bash(rg *)"
          "Bash(fd *)"
          "Bash(tree *)"
          "Bash(head *)"
          "Bash(tail *)"
          "Bash(jq *)"
          "Bash(echo *)"
          "Bash(pwd)"
          "Bash(which *)"
          "Bash(command -v *)"
          "Bash(printenv *)"
          "Bash(readlink *)"
          "Read(*)"
          "WebFetch(domain:github.com)"
          "WebFetch(domain:raw.githubusercontent.com)"
          "WebFetch(domain:pypi.org)"
          "WebFetch(domain:npmjs.com)"
        ];
        ask = [
          "Bash(git commit*)"
          "Bash(git push*)"
          "Bash(git merge*)"
          "Bash(git rebase*)"
          "Bash(git reset*)"
          "Write(*)"
        ];
      };
      hooks = {
        PostToolUse = [
          {
            matcher = "Edit|Write";
            hooks = [
              {
                type = "command";
                command = ''
                  #!/usr/bin/env bash
                  set -euo pipefail

                  file=$(jq -r '.tool_input.file_path // .file_path // empty' <<< "$CLAUDE_TOOL_INPUT" 2>/dev/null || echo "")

                  case "$file" in
                    *.nix)
                      nix fmt "$file" 2>/dev/null || true
                      ;;
                    *.py)
                      ruff format "$file" 2>/dev/null || true
                      ;;
                    *.js|*.ts|*.jsx|*.tsx)
                      dprint fmt "$file" 2>/dev/null || npx prettier --write "$file" 2>/dev/null || true
                      ;;
                    *.md)
                      markdownlint --fix "$file" 2>/dev/null || npx prettier --write "$file" 2>/dev/null || true
                      ;;
                    *.yaml|*.yml)
                      yamlfmt "$file" 2>/dev/null || npx prettier --write "$file" 2>/dev/null || true
                      ;;
                  esac
                '';
              }
            ];
          }
        ];
      };
    };

    agents.code-reviewer = shared.agents.code-reviewer.claude-code;

    commands.changelog = shared.commands.changelog.claude-code;
    commands.commit = shared.commands.commit.claude-code;

    rules = {
      code-quality = shared.rules.code-quality;
      best-practices = shared.rules.best-practices;
    };

    skills = shared.skills;
  };

  home = {
    sessionVariables = {
      CLAUDE_CODE_CONFIG = "${config.home.homeDirectory}/.config/claude-code";
      FORCE_COLOR = "1";
    };
  };

  programs.zsh.shellAliases = {
    cc = "claude-code";
  };
}
