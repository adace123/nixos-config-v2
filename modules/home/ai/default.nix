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
      gemini-cli
      hermes-agent
      pi
    ];

    sessionVariables = {
      FORCE_COLOR = "1";
    };
  };
}
