{
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ./claude.nix
    ./opencode.nix
  ];

  home = {
    packages = with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
      claude-code
      openskills
      agent-browser
      ccstatusline
      ccusage
      ccusage-opencode
      claude-plugins
      amp
      copilot-cli
      gemini-cli
      qwen-code
      beads
    ];

    sessionVariables = {
      FORCE_COLOR = "1";
    };
  };
}
