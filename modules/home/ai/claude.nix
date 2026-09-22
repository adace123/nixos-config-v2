{
  config,
  pkgs,
  inputs,
  ...
}:
let
  shared = import ./shared.nix { inherit inputs pkgs; };
  # Skills shared with other agents (sourced from the mattpocock-skills input)
  commonSkills = import ./skills.nix { inherit inputs; };
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  home.packages = with llmAgents; [
    claude-code
    ccstatusline
    ccusage
  ];

  programs.claude-code = {
    enable = true;
    package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;

    settings = {
      theme = "dark";
      model = "claude-opus-5";
      advisorModel = "fable";
      defaultMode = "auto";
      outputStyle = "concise";
      skipAutoPermissionPrompt = true;
      statusLine = {
        type = "command";
        command = "bash -c 'basename $(dirname $(pwd))/$(basename $(pwd)); git branch --show-current 2>/dev/null | xargs -I{} echo \" ({})\" || true; echo -n \" | \"; npx ccusage@latest statusline' | tr -d '\\n'";
      };
      mcpServers = {
        context7 = {
          type = "http";
          url = "https://mcp.context7.com/mcp";
        };
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
          "Bash(find *)"
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
          "mcp__context7__get-library-docs"
          "mcp__context7__resolve-library-id"
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

    rules.git-worktrees = ''
      # Git Worktree Workflow

      Always implement new features and bug fixes inside a dedicated git worktree.

      ## Workflow
      - Before starting a new feature or bug fix, create a worktree
      - Use descriptive branch names (e.g. `feature/<short-name>`, `fix/<short-name>`)
      - Do all implementation, commits, and tests inside the worktree
      - Never commit directly on the default branch (main/master)
      - After the work is merged, clean up with `git worktree remove <path>`
        and delete the branch
    '';

    skills = {
      code-quality = shared.rules.code-quality;
      best-practices = shared.rules.best-practices;
      # The board's judgement layer for agents the board did not dispatch.
      # Same file Pi gets (see pi.nix); a claude kind is dispatchable from the
      # board too, so both harnesses carry it.
      herdr-kanban = ./skills/herdr-kanban;
    }
    // commonSkills.claudeSkills;

  };

  home = {
    # Allow home-manager to overwrite .bak files from previous activations
    file."${config.home.homeDirectory}/.claude/settings.json".force = true;

    sessionVariables = {
      CLAUDE_CODE_CONFIG = "${config.home.homeDirectory}/.config/claude-code";
      FORCE_COLOR = "1";
    };
  };

  programs.zsh.shellAliases = {
    cc = "claude --permission-mode=auto";
    cca = "claude agents";
  };
}
