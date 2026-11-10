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
  # border option, so the fill is the whole affordance.
  #
  # The Catppuccin base is vendored beside this module because the official
  # flake does not expose it as a standalone theme file. Custom themes must
  # carry every schema token; keep this copy aligned with the pinned theme
  # schema in the OMP source.
  catppuccinTheme = builtins.fromJSON (builtins.readFile ./omp-dark-catppuccin.json);
  userPromptTheme = catppuccinTheme // {
    name = "dark-catppuccin-blocks";
    colors = catppuccinTheme.colors // {
      userMessageBg = "surface0";
      userMessageText = "text";
    };
  };
in
{
  imports = [ inputs.omp.homeManagerModules.default ];

  # OMP's package and Home Manager module come from the official flake input;
  # this module declares our user-specific writable config and settings.
  #
  # The hand-installed brew `omp` (/opt/homebrew/bin/omp, can1357/tap) this
  # replaces has been removed, so `omp` on PATH is this profile's binary.
  programs.omp = {
    enable = true;
    settings = {
      hideThinkingBlock = true;
      # "box" is the "Rounded Box" composer: status line embedded in the top
      # border, compact 2-line prompt.
      composer.shape = "box";
      # Claude-Code-style next-prompt suggestion: after each completed turn
      # the model predicts your next message as ghost text in the empty
      # composer (Tab/→ inserts without sending). Costs one extra billed
      # request per turn (counted in /stats).
      composer.predictions = true;
      # Nerd Font glyphs for icons/symbols; requires a Nerd Font in the terminal
      # (or a Glyph Protocol terminal, which ships icons in-band).
      symbolPreset = "nerd";
      theme.dark = "dark-catppuccin-blocks";
      # No native browser. The `browser` eval prelude (Puppeteer, cmux/Tern
      # surfaces, relay, CDP) is disabled outright; the `browser-routing` skill
      # sends web work to ego lite when a UI or the signed-in profile is needed
      # and to agent-browser when it is not. This also stops OMP dropping
      # browser MCP servers from discovery, which it does while the built-in
      # prelude is callable.
      browser.enabled = false;
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
        # Normal interactive work: commandcode deepseek-v4.1-flash (native
        # vision, 1M ctx, 66K max out). Thinking level pins reasoning effort;
        # high is the default. The GOAT plan gives this model the largest
        # allowance (~256k requests/month) and its $0.003 cache-read rate is
        # the cheapest reasoning model there, so long sessions stay cheap.
        default = "commandcode/deepseek/deepseek-v4.1-flash:high";
        # Fast, cheap utility work: reads, searches, titles, handoffs. Nothing
        # reasons from its output, so the cheapest bulk model wins — MiMo
        # Flash at $0.14/$0.28 per 1M undercuts the DeepSeek default and has no
        # thinking levels to pay for.
        smol = "commandcode/xiaomi/mimo-v2.6-flash";
        # Thorough reasoning where latency is fine: reviewer agent, hard
        # problems. Muse is full-size but agentic-tuned and cross-family from
        # the DeepSeek default; the contributor endpoint is the cheap one
        # ($0.10/$0.20 per 1M) and carries the same paid/training opt-in as the
        # advisor entry. GOAT allows ~90.9k requests/month on it.
        slow = "commandcode/meta/muse-spark-1.3-contributor:high";
        # Passive per-turn review (see `advisor` below): deliberately
        # cross-family from the DeepSeek default for independent judgment.
        # GLM-5.3-Flash at high effort is the same reviewer Pi's rpiv-advisor
        # points at ($0.15/$0.50 per 1M, 1M ctx) — a full-strength flash model
        # rather than a contributor endpoint, and still cheap per turn.
        advisor = "commandcode/z-ai/glm-5.3-flash:high";
        # General subagent work. Same model as `default` so parallel workers
        # draw on the plan's largest allowance (~256k requests/month) instead
        # of draining a small one.
        task = "commandcode/deepseek/deepseek-v4.1-flash:high";
        # Plan-mode architecture: cross-family from DeepSeek/Muse/GLM, 45.4,
        # 1M context, ~1.3k requests/month for bursty planning. `xhigh` because
        # this model declares low/medium/xhigh and no plain `high`.
        plan = "commandcode/Qwen/Qwen3.8-Max-0902:xhigh";
        # UI/UX work: the highest-scored model on the plan (56.0) with native
        # vision and 1M context, but only ~$10/month. Designer runs are
        # occasional, and the fallback chain drops to Qwen when it runs out.
        designer = "commandcode/claude-sonnet-5-5:medium";
        # Commit messages: single-shot, diff-heavy, judgment over speed.
        # Haiku 5.5 scores 43.4 at $0.10/$0.50 per 1M (~29.9k requests/month).
        # The commandcode entry declares no thinking levels, so no `:effort`;
        # the 1M window bills at the long-context tier past 100k input, which
        # commit diffs never reach.
        commit = "commandcode/claude-haiku-5-5";
        # Titles, memory summaries, speech cleanup: cheapest output wins, and
        # MiMo Flash's 1M context keeps long session summaries safe.
        tiny = "commandcode/xiaomi/mimo-v2.6-flash";
        # Image inspection: a declared-vision model with 1M context and a $40
        # allowance. The DeepSeek default is vision-capable on its own entry,
        # hence it backs the fallback.
        vision = "commandcode/google/gemini-3.8-flash:medium";
      };
      # Independent security review: MiMo V2.6 Pro is a distinct family from
      # the DeepSeek default, the Muse reviewer, and the Qwen planner; it
      # scores 46.3 at $0.435/$0.87 per 1M. The entry declares no thinking
      # levels, so no `:effort` suffix.
      task.agentModelOverrides.security-reviewer = "commandcode/xiaomi/mimo-v2.6-pro";
      # The reviewer and security-reviewer already are the independent check;
      # stacking the advisor on them doubles review cost for a second opinion
      # that is the same model.
      task.agentAdvisor = {
        reviewer = "off";
        security-reviewer = "off";
      };
      # Retry fallback chains: the active chat model's primary is its
      # `modelRoles.<role>` above; these are the ordered fallbacks walked on
      # provider errors (429s, quota walls, outages) when
      # `retry.modelFallback` is on (the default). Every role, primary and
      # fallback, is a commandcode selector, so these cover a model-level
      # quota wall or a single upstream model going down — not a full
      # provider outage. Cross-family where it matters: default/slow fall back
      # across DeepSeek/Muse/GLM so one model failing doesn't kill the turn.
      # The Muse contributor endpoint stays out of the plan/task chains so an
      # outage there cannot take three roles with it and data-use exposure is
      # limited to the roles that already use it as a primary. smol/tiny/commit
      # fallbacks pin `:low` effort to stay cheap — nothing reasons from their
      # output.
      retry.fallbackChains = {
        default = [
          "commandcode/meta/muse-spark-1.3-contributor:high"
          "commandcode/z-ai/glm-5.3-flash:high"
        ];
        smol = [
          "commandcode/z-ai/glm-5.3-flash:low"
          "commandcode/deepseek/deepseek-v4.1-flash:low"
        ];
        slow = [
          "commandcode/deepseek/deepseek-v4.1-flash:high"
          "commandcode/z-ai/glm-5.3-flash:high"
        ];
        advisor = [
          "commandcode/meta/muse-spark-1.3-contributor:high"
          "commandcode/deepseek/deepseek-v4.1-flash:high"
        ];
        task = [
          "commandcode/z-ai/glm-5.3-flash:high"
        ];
        plan = [
          "commandcode/xai/grok-4.7:high"
          "commandcode/z-ai/glm-5.3-flash:high"
        ];
        designer = [
          "commandcode/Qwen/Qwen3.8-Max-0902:xhigh"
        ];
        commit = [
          "commandcode/deepseek/deepseek-v4.1-flash:low"
        ];
        tiny = [
          "commandcode/deepseek/deepseek-v4.1-flash:low"
        ];
        vision = [
          "commandcode/deepseek/deepseek-v4.1-flash:high"
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
        # Quietest available: no hide-advisor knob exists (advisor cards
        # always render when notes deliver), so minimise cards instead of
        # hiding them. Review every 10th eligible update, accept at most
        # one non-blocker note per update, only blockers wake a finished
        # turn, and concerns cool down for 5 primary turns after one
        # steers. Blockers always break through.
        reviewInterval = 10;
        maxNotesPerUpdate = 1;
        continueSeverity = "blocker";
        immuneTurns = 5;
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
  # in-repo skill Pi also installs. browser-routing is OMP-only: it replaces
  # the disabled built-in browser with ego lite / agent-browser.
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
    ".omp/agent/skills/browser-routing" = {
      source = ./skills/browser-routing;
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
