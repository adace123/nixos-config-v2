{
  config,
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  llmAgents = inputs.llm-agents.packages.${system};
  collie = inputs.collie.packages.${system}.collie;
  herdrCore = llmAgents.herdr-core;
in
# Collie: the phone UI for the agents running in this host's Herdr core.
#
# There is no herdr-app on a headless VPS, so the core is what holds every
# terminal the phone sees; the unit below starts it at boot instead of at the
# first `hc` command. Both the core and the bridge are per-user, hence linger —
# without it the user manager stops at logout and the socket (and Collie's own
# unit) goes with the SSH session.
#
# The bridge itself is still registered by `collie start` (upstream ships no
# NixOS module for it). It writes a systemd --user unit whose ExecStart pins this
# store path, so after `just update-input collie` run `collie start` again as
# nixos: the weekly GC drops the old path once the next generation stops
# referencing it.
{
  environment.systemPackages = [
    collie
    herdrCore
    # The harnesses the phone can start from its + New page. Claude Code needs
    # `collie hooks install claude` once per user for Chat and History; omp is
    # read from its own session logs and needs nothing.
    #
    # omp comes from llm-agents rather than the repo's own `omp` flake input on
    # purpose: that input builds omp from source, and its `omp-native` step is a
    # bun compile whose peak OOMed this 2 OCPU / 12 GB guest twice (2026-11-08),
    # wedging it hard enough to need an OCI reset. llm-agents ships the same
    # program prebuilt through cache.numtide.com.
    llmAgents.claude-code
    llmAgents.omp
  ];

  users.users.nixos.linger = true;

  # `hc server start` returns once the core is up (verified: it daemonizes), so
  # a oneshot with RemainAfterExit is the right shape. ExecStop parks the core.
  systemd.user.services.herdr-core = {
    description = "herdr-core: terminals that keep running";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${herdrCore}/bin/hc server start";
      ExecStop = "${herdrCore}/bin/hc server stop";
    };
  };

  # The bridge reads ~/.config/collie/.env once at startup. Render it from the
  # same secret Caddy's vhost uses so the public name cannot drift between the
  # two, and symlink it in place rather than hand-writing it on the host.
  sops.templates."collie-env" = {
    content = ''
      COLLIE_MUX=herdr-core
      # Caddy terminates TLS on :443 for every other vhost here, so Collie
      # publishes nothing of its own and stays on loopback.
      COLLIE_SKIP_SERVE=1
      COLLIE_TELEMETRY=0
      COLLIE_PUBLIC_HOSTS=${config.sops.placeholder.collie-domain}
      COLLIE_PUBLIC_URL=https://${config.sops.placeholder.collie-domain}
      COLLIE_ALLOWED_ORIGINS=https://${config.sops.placeholder.collie-domain}
    '';
    owner = "nixos";
    # 0600, not 0400: `collie start` writes its multiplexer choice back into the
    # file, and the owner has to be able to.
    mode = "0600";
  };

  systemd.tmpfiles.rules = [
    # The parent is declared too: `d` creates missing intermediate directories as
    # root, and a root-owned /home/nixos/.config then makes tmpfiles refuse the
    # whole chain as an unsafe path transition, so .env would never be linked.
    "d /home/nixos/.config 0755 nixos users -"
    "d /home/nixos/.config/collie 0700 nixos users -"
    # L+ replaces whatever is there, so a hand-written .env from a trial run is
    # taken over by the rendered one.
    "L+ /home/nixos/.config/collie/.env - - - - ${config.sops.templates."collie-env".path}"
  ];
}
