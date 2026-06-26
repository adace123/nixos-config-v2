{
  pkgs,
  inputs,
  ...
}:

let
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  hermesAgent = llmAgents.hermes-agent;
  hermesDesktop = llmAgents.hermes-desktop;

  hermesAgentWithDesktop = pkgs.runCommand "hermes-agent-with-desktop" { } ''
    mkdir -p $out/bin

    for bin in ${hermesAgent}/bin/*; do
      name=$(basename "$bin")
      if [ "$name" != "hermes" ] && [ "''${name#.}" = "$name" ]; then
        ln -s "$bin" "$out/bin/$name"
      fi
    done

    cat > $out/bin/hermes <<'EOF'
    #!${pkgs.runtimeShell}
    case "''${1-}" in
      desktop|gui)
        shift
        exec ${hermesDesktop}/bin/hermes-desktop "$@"
        ;;
    esac

    exec ${hermesAgent}/bin/hermes "$@"
    EOF
    chmod +x $out/bin/hermes
  '';
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
      hermesAgentWithDesktop
      hermesDesktop
      pi
      omp
    ];

    sessionVariables = {
      FORCE_COLOR = "1";
    };
  };
}
