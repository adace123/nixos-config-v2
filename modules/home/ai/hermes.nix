{
  config,
  inputs,
  pkgs,
  ...
}:

let
  hermesAgent = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  # ── Hermes config.yaml ──────────────────────────────────────────
  # Managed via Nix — do NOT use `hermes config set KEY VAL` or
  # the atomic-replace will fail (symlinked to nix store).

  home.packages = [ hermesAgent.minimal ];

  sops.secrets.opencode-api-key = { };

  home.file.".hermes/config.yaml" = {
    force = true;
    text = builtins.toJSON {
      model = {
        default = "deepseek-v4-flash";
        provider = "opencode-go";
      };
      terminal = {
        backend = "local";
        persistent_shell = true;
      };
      memory = {
        memory_enabled = true;
        provider = "holographic";
      };
      agent = {
        show_reasoning = false;
      };
      approvals.mode = "manual";
      compression.enabled = true;
      toolsets = [ "all" ];
    };
  };

  sops.templates.".hermes/.env" = {
    content = ''
      OPENCODE_GO_API_KEY=${config.sops.placeholder.opencode-api-key}
      OPENCODE_ZEN_API_KEY=${config.sops.placeholder.opencode-api-key}
    '';
    path = "${config.home.homeDirectory}/.hermes/.env";
  };

}
