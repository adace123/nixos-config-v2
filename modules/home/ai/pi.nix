{
  pkgs,
  inputs,
  config,
  ...
}:

let
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
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
      defaultModel = "deepseek-v4-flash";
      defaultThinkingLevel = "high";
      quietStartup = true;
      packages = [
        "git:github.com/otahontas/pi-coding-agent-catppuccin"
        "npm:pi-tool-display"
        "npm:pi-powerline-footer"
        "npm:pi-mcp-adapter"
        "npm:pi-subagents"
        # npm's latest pi-web-access (0.13.0) predates TinyFish support (added in 0.14.0) — pin the GitHub release
        "git:github.com/nicobailon/pi-web-access@v0.17.1"
        "npm:context-mode"
        "npm:@juicesharp/rpiv-todo"
      ];
    };
  };

  # pi-mcp-adapter reads MCP servers from mcp.json, not Pi's settings.json.
  # Keep this in the Pi agent directory so the configuration is global for Pi.
  home.file.".pi/agent/mcp.json".text = builtins.toJSON {
    mcpServers = {
      context7 = {
        url = "https://mcp.context7.com/mcp";
      };
      grep-mcp = {
        url = "https://mcp.grep.app";
      };
    };
  };

  # Custom skills. ~/.pi/agent/skills/ is a global pi skill location, so
  # skills placed there are auto-discovered at startup (no settings change
  # needed). Each skill is a directory containing a SKILL.md per the Agent
  # Skills spec (https://agentskills.io/specification).
  home.file.".pi/agent/skills/commit-all" = {
    source = ./skills/commit-all;
    recursive = true;
  };

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
      summaryModel = "opencode-go/deepseek-v4-flash";
    };
    path = "${config.home.homeDirectory}/.config/pi/web-search.json";
  };
}
