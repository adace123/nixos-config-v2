{
  pkgs,
  inputs,
  config,
  ...
}:

let
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  # Skills shared with other agents (sourced from the mattpocock-skills input)
  commonSkills = import ./skills.nix { inherit inputs; };
in

{
  programs.pi-coding-agent = {
    enable = true;
    package = llmAgents.pi;
    extraPackages = [
      pkgs.git
      pkgs.nodejs
      pkgs.bun
    ];
    settings = {
      hideThinkingBlock = true;
      defaultProvider = "opencode-go";
      defaultModel = "deepseek-v4.1-flash";
      defaultThinkingLevel = "high";
      quietStartup = true;
      packages = [
        "git:github.com/otahontas/pi-coding-agent-catppuccin"
        "npm:pi-tool-display"
        "npm:pi-powerline-footer"
        "npm:pi-mcp-adapter"
        "npm:pi-subagents"
        "git:github.com/nicobailon/pi-web-access"
        "npm:context-mode"
        "npm:@juicesharp/rpiv-todo"
        "npm:@juicesharp/rpiv-ask-user-question"
        "npm:@juicesharp/rpiv-advisor"
        "npm:@ff-labs/pi-fff"
      ];
    };
  };

  # pi-mcp-adapter reads MCP servers from mcp.json, not Pi's settings.json.
  # Keep this in the Pi agent directory so the configuration is global for Pi.
  #
  # Custom skills. ~/.pi/agent/skills/ is a global pi skill location, so
  # skills placed there are auto-discovered at startup (no settings change
  # needed). Each skill is a directory containing a SKILL.md per the Agent
  # Skills spec (https://agentskills.io/specification). Common skills come
  # from ./skills.nix; Pi-only skills are declared here.
  home.file = {
    # pi installs its npm extensions with `npm install --prefix
    # ~/.pi/agent/npm`, and npm reads the `.npmrc` of that prefix as its
    # *project* config — so this only affects pi's package installs/updates.
    #
    # It overrides prefer-offline=true from ~/.npmrc, which npm maps to HTTP
    # cache mode `force-cache`: cached registry metadata is reused no matter how
    # stale it is. The registry serves two packuments per package (compressed
    # "corgi" and full) and they are cached separately (the response carries
    # `vary: accept`), so the full copy is only refreshed by a full-metadata
    # request. Once it lags behind, it advertises a `latest` dist-tag taken from
    # the fresh corgi copy while missing that version, and `pi update
    # --extensions` dies with `ETARGET No matching version found for <pkg>@<v>`.
    # prefer-offline=false restores normal revalidation (metadata is
    # `max-age=300`) and keeps updates working.
    ".pi/agent/npm/.npmrc".text = "prefer-offline=false\n";

    ".pi/agent/mcp.json".text = builtins.toJSON {
      mcpServers = {
        context7 = {
          url = "https://mcp.context7.com/mcp";
        };
        grep-mcp = {
          url = "https://mcp.grep.app";
        };
      };
    };

    ".pi/agent/skills/commit-all" = {
      source = ./skills/commit-all;
      recursive = true;
    };

    # The board's judgement layer: when to note vs move vs block vs file a card,
    # which is the part the dispatch protocol (a prompt, so every line costs)
    # does not carry. The verbs stay in `herdr-kanban help`, which the skill
    # points at rather than quoting — a third copy of the protocol block would
    # be a third thing to drift. Global scope is deliberate: the board is
    # machine-wide across workspaces, so a dispatched agent is not the only one
    # that needs to find it. See docs/kanban.md.
    ".pi/agent/skills/herdr-kanban" = {
      source = ./skills/herdr-kanban;
      recursive = true;
    };

    # OpenCode Go/Zen reject a request without `x-opencode-session` with
    # `400 MissingSessionID`. Pi sends it on its own requests, but that merge
    # lives in the coding agent's stream wrapper, so an extension running a
    # model itself — `@juicesharp/rpiv-advisor`'s reviewer side-call — never gets
    # it and the tool fails while the executor works. This extension registers
    # the session's own id as a provider header on `session_start`, which lands
    # on both paths and makes extension side-calls work. See the file header and
    # docs/ai.md.
    ".pi/agent/extensions/opencode-session.ts".source = ./pi-extensions/opencode-session.ts;

    ".config/rpiv-advisor/advisor.json".text = builtins.toJSON {
      modelKey = "opencode-go/glm-5.3-flash";
      effort = "high";
    };
  }
  // commonSkills.piFiles;

  sops.secrets = {
    tinyfish-api-key = { };
  };

  # Render the TinyFish API key into web-search.json at activation.
  # pi-web-access v0.17+ resolves the config file from PI_CODING_AGENT_DIR,
  # then $XDG_CONFIG_HOME/pi, before falling back to ~/.pi — and this
  # machine exports XDG_CONFIG_HOME=/Users/aaron/.config, so the runtime
  # reads ~/.config/pi/web-search.json, NOT ~/.pi/web-search.json. Writing
  # to the wrong path silently ignores summaryModel and falls back to
  # github-copilot/claude-haiku-4.5 for summaries.
  # config.sops.secrets.<name> is a module option, not the decrypted value —
  # the placeholder is substituted with the real key by sops-install-secrets.
  sops.templates.".config/pi/web-search.json" = {
    content = builtins.toJSON {
      tinyfishApiKey = config.sops.placeholder.tinyfish-api-key;
      provider = "tinyfish";
      autoOpenBrowser = false;
      summaryModel = "opencode-go/deepseek-v4.1-flash";
    };
    path = "${config.home.homeDirectory}/.config/pi/web-search.json";
  };
}
