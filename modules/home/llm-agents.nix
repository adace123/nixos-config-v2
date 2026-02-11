{
  config,
  pkgs,
  inputs,
  ...
}:

{
  home = {
    packages = with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
      # AI Coding Agents
      claude-code # Anthropic's Claude Code CLI
      opencode # AI coding agent built for the terminal

      # Utilities
      openskills # Universal skills loader for AI coding agents
      openclaw
      agent-browser

      # Claude Code Ecosystem
      ccstatusline # Customizable status line for Claude Code CLI
      ccusage # Usage analysis tool for Claude Code
      claude-plugins # CLI tool for managing Claude Code plugins

      # Optional: Uncomment based on your needs
      amp # Sourcegraph Amp CLI (unfree)
      copilot-cli # GitHub Copilot CLI (unfree)

      # Alternative/Additional Agents
      gemini-cli # Google Gemini CLI
      qwen-code # Qwen3-Coder CLI
    ];

    # Session variables for AI tools
    sessionVariables = {
      # Claude Code configuration
      CLAUDE_CODE_CONFIG = "${config.home.homeDirectory}/.config/claude-code";

      # Enable colored output for AI tools
      FORCE_COLOR = "1";
    };

    # Create config directories
    file.".config/claude-code/.keep".text = "";
    file.".config/opencode/.keep".text = "";
  };
}
