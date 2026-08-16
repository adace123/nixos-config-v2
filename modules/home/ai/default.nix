{
  pkgs,
  inputs,
  ...
}:

let
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  hermesAgent = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system};
in

{
  imports = [
    ./claude.nix
    ./hermes.nix
    ./opencode.nix
    ./pi.nix
  ];

  home = {
    packages = with llmAgents; [
      claude-code
      ccstatusline
      ccusage
      hermesAgent.default
      omp
    ];

    sessionVariables = {
      FORCE_COLOR = "1";
    };
  };
}
