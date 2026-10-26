{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  # User-level MCP servers for OMP's native provider: it reads exactly
  # ~/.omp/agent/mcp.json (discovery/builtin.ts). Kept in sync with the Pi
  # user-level file in pi.nix. Installed as a writable regular file for the
  # same reason as config.yml — `/mcp` toggles servers by rewriting the
  # enable lists in this file, and a read-only store symlink would fail with
  # EACCES. Declared values are re-asserted on the next switch.
  #
  # OMP has no per-server `description` field (only `instructions`), so the
  # descriptions pi.nix sets are deliberately absent: OMP shows the server name
  # plus whatever instructions the server itself returns.
  mcpConfig = pkgs.writeText "omp-mcp.json" (
    builtins.toJSON {
      mcpServers = {
        context7 = {
          type = "http";
          url = "https://mcp.context7.com/mcp";
        };
        grep-mcp = {
          type = "http";
          url = "https://mcp.grep.app";
        };
      };
    }
  );

  # Catppuccin as shipped, with the user-prompt bubble lifted off the page:
  # the built-in maps userMessageBg to `mantle` (#181825) on a `base` (#1e1e2e)
  # terminal, so the bubble the renderer fills is nearly invisible. surface0
  # (#313244) is the palette's own raised surface; OMP's user bubble has no
  # border option, so the fill is the whole affordance. Derived from the theme
  # file in the flake input rather than copied, so the rest of the palette
  # tracks upstream.
  catppuccinTheme = builtins.fromJSON (
    builtins.readFile "${inputs.omp}/packages/tui/src/theme/defaults/dark-catppuccin.json"
  );
  userPromptTheme = catppuccinTheme // {
    name = "dark-catppuccin-blocks";
    colors = catppuccinTheme.colors // {
      userMessageBg = "surface0";
      userMessageText = "text";
    };
  };
in
{
  imports = [
    inputs.omp.homeManagerModules.default
  ];

  # OMP (oh-my-pi), Nix-managed: package plus ~/.omp/agent/config.yml,
  # written declaratively on every switch (writable regular file, so OMP's
  # runtime rewrites still work and are re-asserted next switch).
  #
  # The hand-installed brew `omp` (/opt/homebrew/bin/omp, can1357/tap) this
  # replaces has been removed, so `omp` on PATH is this profile's binary.
  programs.omp = {
    enable = true;
    # Prebuilt from cache.numtide.com via the llm-agents input (currently
    # 18.12.2 in the lock vs 18.12.6 on upstream main). Upstream's own flake
    # builds from source, which costs a ~15min bun build; the module itself
    # still comes from the omp flake input above.
    package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp;
    settings = {
      hideThinkingBlock = true;
      # "box" is the "Rounded Box" composer: status line embedded in the top
      # border, compact 2-line prompt.
      composer.shape = "box";
      # Nerd Font glyphs for icons/symbols; requires a Nerd Font in the terminal
      # (or a Glyph Protocol terminal, which ships icons in-band).
      symbolPreset = "nerd";
      theme.dark = "dark-catppuccin-blocks";
      browser.headless = false;
      # The home-manager module reinstalls config.yml on every switch, and the
      # declarative file has no `setupVersion` (OMP writes that itself when the
      # wizard finishes). OMP therefore reads the version as 0, treats setup as
      # never completed, and replays the onboarding wizard on the next launch
      # (every start, if the wizard is dismissed with Ctrl-C, which skips the
      # completion write). Every choice its scenes ask for is declared here
      # anyway; `omp setup` still forces the full wizard when it is wanted.
      startup.setupWizard = false;
      tools = {
        approvalMode = "always-ask";
        # Per-tool overrides are honoured in every mode. `always-ask` only
        # auto-approves read-tier tools, so allow the write-tier ones — `edit`
        # (also covers moves/renames and `apply_patch`), `write`, and
        # `ast_edit` — the same way `bash` is allowed. Anything still exec-tier
        # (eval, browser, task) keeps prompting.
        approval.bash = "allow";
        approval.edit = "allow";
        approval.write = "allow";
        approval.ast_edit = "allow";
      };
      # Transcript noise: `hideToolActivity` keeps tool calls/results out of
      # the transcript (the TUI still shows status rows), which also quiets
      # web_search output. There is no per-tool "hide web_search results"
      # knob — `web_search.enabled = false` is the only way to silence it, and
      # that removes the tool entirely.
      display.hideToolActivity = true;
      modelRoles = {
        # Normal interactive work: opencode-go deepseek-v4.1-flash (native
        # vision, 1M ctx, 384K max out). Thinking level pins reasoning effort;
        # high is the default.
        default = "opencode-go/deepseek-v4.1-flash:high";
        # Fast, cheap utility work: reads, searches, titles, handoffs. Nothing
        # reasons from its output, so the cheapest bulk model wins.
        smol = "opencode-go/mimo-v2.5";
        # Thorough reasoning where latency is fine: reviewer agent, hard
        # problems. Muse is full-size but lightly served (45k req/5h on Go vs
        # 220 for glm-5.3:max), agentic-tuned, and cross-family from the
        # DeepSeek default. Needs the "paid endpoints that train on request
        # data" opt-in in the OpenCode Console privacy settings.
        slow = "opencode-go/muse-spark-1.3-contributor:high";
        # Passive per-turn review (see `advisor` below): deliberately
        # cross-family from the DeepSeek default for independent judgment.
        # GLM-5.3-Flash at high effort is the same reviewer Pi's rpiv-advisor
        # points at ($0.15/$0.50 per 1M, 1M ctx) — a full-strength flash model
        # rather than a contributor endpoint, and still cheap per turn.
        advisor = "opencode-go/glm-5.3-flash:high";
      };
      # Retry fallback chains: the active chat model's primary is its
      # `modelRoles.<role>` above; these are the ordered fallbacks walked on
      # provider errors (429s, quota walls, outages) when
      # `retry.modelFallback` is on (the default). Cross-family where it
      # matters: default/slow fall back across DeepSeek/Muse/GLM so one
      # provider outage doesn't kill the turn. smol fallbacks pin `:low`
      # effort to stay cheap — nothing reasons from smol output.
      retry.fallbackChains = {
        default = [
          "opencode-go/muse-spark-1.3-contributor:high"
          "opencode-go/glm-5.3-flash:high"
        ];
        smol = [
          "opencode-go/glm-5.3-flash:low"
          "opencode-go/deepseek-v4.1-flash:low"
        ];
        slow = [
          "opencode-go/deepseek-v4.1-flash:high"
          "opencode-go/glm-5.3-flash:high"
        ];
        advisor = [
          "opencode-go/muse-spark-1.3-contributor:high"
          "opencode-go/deepseek-v4.1-flash:high"
        ];
      };
      # Autonomous memory: project-scoped summaries/lessons from persisted
      # sessions, injected as a Memory Guidance block at startup
      # (`memory://root`, `memory://root/MEMORY.md`, `memory://root/learned.md`
      # via `read`). `autolearn` adds the `learn` tool so durable lessons land
      # in `learned.md` (newest-first, capped, secret-redacted).
      memory.backend = "local";
      autolearn.enabled = true;
      # TUI polish: `nerd` status line matches `symbolPreset = "nerd"` above;
      # `subagentLivePreview` adds each pinned agent's current tool call under
      # its jump-list row.
      statusLine.preset = "nerd";
      # `tui.mouse` stays off. It enables inline click-to-focus on live subagent
      # cards and jump-list rows, but the capture it turns on (`?1000h`/`?1003h`)
      # makes the terminal send wheel reports to OMP, and OMP's inline handler
      # consumes every SGR report while acting only on clicks and motion — the
      # main transcript (native scrollback, there is no app-level scroll)
      # therefore never scrolls on wheel. Upstream documents the cost as "wheel
      # scroll becomes Shift+wheel while on", and stray tracking-state changes
      # from child TUIs make even that intermittent. Click-to-focus remains
      # available through the Agent Hub (Alt+A); plain wheel scrolling is worth
      # more than one-click focus, and capture also steals native selection
      # (Shift+drag while on).
      tui.mouse = false;
      display.subagentLivePreview = true;
      advisor = {
        enabled = true;
      };
    };
  };

  # Same writable-file treatment as config.yml (see mcpConfig above).
  home.activation.ompMcpConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.omp/agent"
    run install -m 600 ${mcpConfig} "$HOME/.omp/agent/mcp.json"
  '';

  # OMP's native skill provider scans ~/.omp/agent/skills, and its scanner
  # follows directory symlinks (`isDirectory() || isSymbolicLink()`), so the
  # store links created here are discovered like real dirs. The two interview
  # skills come from the same mattpocock input Pi uses; commit-all is the
  # in-repo skill Pi also installs.
  # Keybindings live in a separate keybindings.yml (never in config.yml).
  # A plain store symlink is fine here, unlike config.yml/mcp.json: OMP only
  # reads this file, migrating legacy names in memory (write-back happens
  # solely for legacy keybindings.json or renamed actions, neither of which
  # this canonical file triggers).
  home.file = {
    ".omp/agent/themes/dark-catppuccin-blocks.json" = {
      text = builtins.toJSON userPromptTheme + "\n";
    };
    ".omp/agent/skills/grilling" = {
      source = "${inputs.mattpocock-skills}/skills/productivity/grilling";
      recursive = true;
    };
    ".omp/agent/skills/grill-me" = {
      source = "${inputs.mattpocock-skills}/skills/productivity/grill-me";
      recursive = true;
    };
    ".omp/agent/skills/commit-all" = {
      source = ./skills/commit-all;
      recursive = true;
    };
    # The /tree branch-jump actions are unbound by default; Alt+[ / Alt+]
    # step between visible branches without opening the tree. (Ghostty sends
    # Option as Alt via macos-option-as-alt.)
    ".omp/agent/keybindings.yml".text = ''
      app.tree.previousBranch: Alt+[
      app.tree.nextBranch: Alt+]
    '';
  };
}
