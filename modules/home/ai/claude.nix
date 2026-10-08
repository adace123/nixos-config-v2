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
      model = "claude-opus-5-5";
      advisorModel = "opus";
      defaultMode = "auto";
      # Model routing for delegated work. The main loop keeps Opus, the
      # subagents that do judgement work state their own model outright
      # (`Explore` below, `code-reviewer` in shared.nix), and this variable
      # covers everything else — notably the built-in `general-purpose` agent.
      #
      # Sonnet 5.5 rather than Haiku 5.5: Anthropic's own benchmarks put
      # Sonnet 5.5 ahead of Opus 5.5 on Terminal-Bench 4.0 (70.6% vs 66.4%)
      # at half the token price, while Haiku 5.5 scores 39.2% there. Haiku is
      # fine for finding and reading code, not for completing multi-step work.
      #
      # CLAUDE_CODE_SUBAGENT_MODEL_FORCE is deliberately unset: it flattens
      # every subagent onto one model with no way to exempt an agent, which
      # would drag code-reviewer down along with the rest.
      #
      # This variable does not reach the built-in Explore/Plan agents — that is
      # what the `Explore` override below is for.
      env = {
        CLAUDE_CODE_SUBAGENT_MODEL = "claude-sonnet-5-5";
      };
      outputStyle = "concise";
      skipAutoPermissionPrompt = true;
      # Declared here (not toggled via /plugin) because settings.json is a
      # read-only home-manager symlink into the Nix store.
      enabledPlugins = {
        "cc-plugin-you-should-know@builtin" = true;
      };
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
          "Bash(git commit*)"
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
          "Bash(herdr *)"
          "Read(*)"
          "WebFetch(domain:github.com)"
          "WebFetch(domain:raw.githubusercontent.com)"
          "WebFetch(domain:pypi.org)"
          "WebFetch(domain:npmjs.com)"
          "mcp__context7__get-library-docs"
          "mcp__context7__resolve-library-id"
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

    # The built-in Explore agent inherits the main conversation's model, so on
    # an Opus session it explores on Opus. A user-level agent named `Explore`
    # overrides the built-in and keeps its own `model` field — the documented
    # way to cheapen exploration without FORCE-ing every other subagent.
    #
    # Haiku 5.5 is Anthropic's own recommendation for this shape of work
    # ("compaction, summarization, or subagent work") and costs 20x less than
    # Sonnet 5.5 for prompts up to 100K tokens. The reasoning that consumes the
    # result stays in the Opus main loop, so a weaker model here is not the
    # quality risk it would be for code-reviewer.
    #
    # This replaces the built-in definition, so the prompt below restates its
    # behaviour: read-only tools, no CLAUDE.md or git snapshot (pure latency for
    # research), and the thoroughness levels Claude passes with each call.
    agents.Explore = ''
      ---
      name: Explore
      description: Fast read-only search agent for locating code in an unfamiliar codebase. Use it to find files, symbols and call sites or to trace how something works, without changing anything.
      tools: Read, Grep, Glob, Bash
      model: claude-haiku-5-5
      omitClaudeMd: true
      ---

      You are a fast, read-only codebase exploration agent: you locate and
      report, you do not change or judge code.

      - Locate with Glob (by path) and Grep (by content) before reading
        anything. Prefer a few targeted searches over reading whole trees.
      - You have read-only tools. Never write or edit files, and never run a
        command that changes state.
      - Claude passes a thoroughness level; honour it:
        - *quick* — answer from one or two searches, then stop.
        - *medium* — search the likely locations and follow obvious loose ends.
        - *very thorough* — trace every relevant call site and configuration
          path before answering.
      - Your final message is the entire output; nothing else reaches Claude.
        Give file paths with line numbers, the smallest excerpts that carry the
        answer, and a direct statement of what you found.
      - State plainly when something does not exist, when two places disagree,
        or when you could not determine the answer. Do not guess.

    '';

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
