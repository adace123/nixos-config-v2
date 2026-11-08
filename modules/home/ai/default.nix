{
  inputs,
  pkgs,
  ...
}:

let
  # Prebuilt, cache-backed agent CLIs; see claude.nix and herdr.nix.
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [
    ./claude.nix
    ./hermes.nix
    ./pi.nix
    ./herdr/herdr.nix
    ./omp.nix
  ];

  # The headless half of the browser routing in omp.nix: a native binary plus
  # its own version-matched `skills`. llm-agents tracks upstream releases and
  # substitutes from cache.numtide.com, so the version moves with
  # `just update-input llm-agents` instead of a version string here.
  home.packages = [ llmAgents.agent-browser ];
}
