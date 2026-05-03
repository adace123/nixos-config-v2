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
      agent-browser
      ccstatusline
      ccusage
      ccusage-opencode
      gemini-cli
      hermes-agent
    ];

    sessionVariables = {
      FORCE_COLOR = "1";
    };
  };
}
