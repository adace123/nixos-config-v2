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

  sops.secrets = {
    tinyfish-api-key = { };
  };

  # Render the TinyFish API key into ~/.pi/web-search.json at activation.
  # config.sops.secrets.<name> is a module option, not the decrypted value —
  # the placeholder is substituted with the real key by sops-install-secrets.
  sops.templates.".config/pi/web-search.json" = {
    content = builtins.toJSON {
      tinyfishApiKey = config.sops.placeholder.tinyfish-api-key;
      provider = "tinyfish";
    };
    path = "${config.home.homeDirectory}/.pi/web-search.json";
  };
}
