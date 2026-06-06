{
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ./claude.nix
    ./hermes.nix
    ./opencode.nix
  ];

  home = {
    packages = with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
      claude-code
      ccstatusline
      ccusage
      hermes-agent
      pi
      omp
    ];

    sessionVariables = {
      FORCE_COLOR = "1";
    };
  };
}
