{
  config,
  inputs,
  pkgs,
  ...
}:
# OpenKnowledge (the wiki): local-first Markdown knowledge base with a browser
# editor and an MCP endpoint, published tailnet-only as wiki.figtreelab.dev via
# the shared Caddy.
#
# One always-on instance over a persistent project directory, which is what the
# package's remote-control model needs: a long-lived server, TLS, a streaming
# reverse proxy, and access control at the edge. The edge here is the tailnet —
# Caddy adds no extra auth, exactly like the hub, Pocket ID and Gatus.
#
# The project is a clone of the private notes repo, so wiki edits are committed
# and pushed back (autoSync mode `full`). The deploy key that does the pushing
# is a repo-scoped write key held in sops.
#
# The package comes from the open-knowledge flake input (a fork that wraps the
# published npm release); see docs/dathomir.md.
let
  openKnowledge = inputs.open-knowledge.packages.${pkgs.stdenv.hostPlatform.system}.default;

  start = pkgs.writeShellApplication {
    name = "open-knowledge-start";
    runtimeInputs = [
      openKnowledge
      pkgs.coreutils
      pkgs.git
      pkgs.openssh
    ];
    text = ''
      cd /var/lib/open-knowledge
      mkdir -p home
      export HOME=/var/lib/open-knowledge/home

      git config --global user.name "OpenKnowledge"
      git config --global user.email "open-knowledge@dathomir"

      # The deploy key is the only credential: repo-scoped, write-enabled, and
      # read here as the service user. IdentitiesOnly keeps ssh from offering
      # anything else first.
      mkdir -p "$HOME/.ssh"
      {
        echo 'Host github.com'
        echo '  IdentityFile ${config.sops.secrets.wiki-deploy-key.path}'
        echo '  IdentitiesOnly yes'
        echo '  StrictHostKeyChecking accept-new'
      } > "$HOME/.ssh/config"
      chmod 600 "$HOME/.ssh/config"

      # An interrupted clone leaves notes/ non-empty without .git, and git will
      # not clone into that. Refuse loudly instead of half-initialising over it;
      # the unit then parks (see StartLimit*) until someone clears the directory.
      if [ -d notes ] && [ ! -d notes/.git ] && [ -n "$(ls -A notes)" ]; then
        echo "notes/ is non-empty but not a git repository — an interrupted first boot." >&2
        echo "Remove /var/lib/open-knowledge/notes, then restart this unit." >&2
        exit 1
      fi
      if [ ! -d notes/.git ]; then
        # shellcheck disable=SC2154 # supplied by the systemd EnvironmentFile
        timeout 120 git clone "$WIKI_GIT_REMOTE" notes
      fi

      cd notes
      if [ ! -d .ok ]; then
        ok init --no-mcp --no-skills < /dev/null
      fi

      # `ok init` also writes project-local copies of its own skill docs for AI
      # editors (.agents/, .claude/, .codex/, .cursor/, .opencode/, .pi/) —
      # --no-skills only covers user-global bundles. They are markdown, so left
      # in place they would be indexed as wiki pages and committed to the notes
      # repo. Remove them, and keep them ignored in case init runs again.
      editors=".agents/ .claude/ .codex/ .cursor/ .opencode/ .pi/"
      for dir in $editors; do
        rm -rf "./''${dir%/}"
      done
      for file in .okignore .git/info/exclude; do
        for dir in $editors; do
          grep -qxF "$dir" "$file" 2>/dev/null || printf '%s\n' "$dir" >> "$file"
        done
      done

      # Per-machine sync mode: pull and push on a schedule, so edits made in the
      # browser reach the notes repo without a manual action. Only seeded when
      # absent — the value is per-machine state, not configuration.
      mkdir -p .ok/local
      if [ ! -f .ok/local/config.yml ]; then
        printf 'autoSync:\n  mode: full\n' > .ok/local/config.yml
      fi

      exec ok start --no-open-browser
    '';
  };
in
{
  users.groups.open-knowledge = { };
  users.users.open-knowledge = {
    isSystemUser = true;
    group = "open-knowledge";
    home = "/var/lib/open-knowledge/home";
  };

  systemd.services.open-knowledge = {
    description = "OpenKnowledge server (wiki)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment = {
      PORT = "8080";
      # Loopback only: Caddy is the single tailnet path in.
      OK_BIND = "127.0.0.1";
      # Caddy stamps forwarding headers, so the server refuses requests unless
      # it has both consented and been told its public origin.
      OK_ALLOW_EXTERNAL = "1";
      # A wiki is idle most of the day; the default 30m idle shutdown would take
      # it down under a browser tab that stops polling.
      OK_IDLE_SHUTDOWN = "off";
      # Never wait on a credential prompt: the unit has no terminal, and a
      # hanging push would hold the service.
      GIT_TERMINAL_PROMPT = "0";
      TZ = "America/Los_Angeles";
    };
    # A transient failure should heal itself, but a broken state dir (an
    # interrupted clone) cannot: park the unit after a handful of attempts
    # rather than crash-looping every 30s forever.
    unitConfig = {
      StartLimitIntervalSec = 600;
      StartLimitBurst = 5;
    };
    serviceConfig = {
      Type = "simple";
      User = "open-knowledge";
      Group = "open-knowledge";
      StateDirectory = "open-knowledge";
      EnvironmentFile = config.sops.templates."open-knowledge-env".path;
      ExecStart = "${start}/bin/open-knowledge-start";
      Restart = "on-failure";
      RestartSec = 30;
    };
  };

  # The public origin and the private repo URL stay out of the repo. The deploy
  # key itself is a separate sops secret, owned by the service user.
  sops.templates."open-knowledge-env" = {
    content = ''
      OK_EXTERNAL_URL=https://${config.sops.placeholder.wiki-domain}
      WIKI_GIT_REMOTE=${config.sops.placeholder.wiki-git-remote}
    '';
    mode = "0400";
  };
}
