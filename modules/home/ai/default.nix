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
      antigravity-cli
      claude-code
      ccstatusline
      ccusage
      hermes-agent
      pi
    ];

    sessionVariables = {
      FORCE_COLOR = "1";
    };
  };
}
