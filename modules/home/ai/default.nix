{
  pkgs,
  inputs,
  lib,
  ...
}:

let
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in

{
  imports = [
    ./claude.nix
    ./hermes.nix
    ./opencode.nix
  ];

  home = {
    packages = with llmAgents; [
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

  # Install pi extensions using activation script
  home.activation.installPiExtensions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${llmAgents.pi}/bin/pi install git:github.com/otahontas/pi-coding-agent-catppuccin
    $DRY_RUN_CMD ${llmAgents.pi}/bin/pi install npm:statusline-pi
    $DRY_RUN_CMD ${llmAgents.pi}/bin/pi install npm:pi-powerline-footer
    $DRY_RUN_CMD ${llmAgents.pi}/bin/pi install npm:pi-web-access
    $DRY_RUN_CMD ${llmAgents.pi}/bin/pi install npm:context-mode
    $DRY_RUN_CMD ${llmAgents.pi}/bin/pi install npm:@juicesharp/rpiv-todo
  '';
}
