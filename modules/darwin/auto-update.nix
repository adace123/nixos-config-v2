{
  config,
  pkgs,
  lib,
  ...
}:

let
  userHome = config.users.users.${config.system.primaryUser}.home;
  cfg = config.services.nix-config-auto-update;
  ompPackage = config.home-manager.users.${config.system.primaryUser}.programs.omp.package;

in
{
  options = {
    services.nix-config-auto-update = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable automatic Nix config updates";
      };

      hour = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = "Hour of the day to check for updates (0-23)";
      };

      minute = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Minute of the hour to check for updates (0-59)";
      };

      autoSwitch = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Build and activate *lockfile-only* updates automatically. A push that
          touches anything besides `flake.lock` is reported and left for a human
          (`just switch`): modules, activation scripts, the justfile and CI all
          run code, so only a reviewed commit may be applied. Activation also
          needs non-interactive root, which a launchd agent only has if sudo is
          configured for it; without that the build is still reported and the
          switch is left to `just switch`.
        '';
      };

      autoFix = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Hand a failed build or activation to `omp` (see `scripts/omp-fix.sh`)
          for a **read-only** diagnosis. The agent neither edits the repository
          nor retries the switch: a build log can carry text from fetched
          sources, so no unattended run may act on it. `just switch` keeps the
          interactive, editing repair.
        '';
      };

      darwinConfigName = lib.mkOption {
        type = lib.types.str;
        description = "Name of the darwinConfiguration output in the flake";
      };

      repoDir = lib.mkOption {
        type = lib.types.str;
        default = "${userHome}/Projects/personal/nixos-config-v2";
        description = "Path to the local nix-config repository";
      };
    };
  };

  config = lib.mkIf config.services.nix-config-auto-update.enable {
    launchd.user.agents.nix-config-auto-update = {
      serviceConfig = {
        Label = "org.nix-community.darwin.auto-update";
        StartCalendarInterval = [
          {
            Hour = config.services.nix-config-auto-update.hour;
            Minute = config.services.nix-config-auto-update.minute;
          }
        ];
        StandardErrorPath = "/tmp/nix-darwin-update.log";
        StandardOutPath = "/tmp/nix-darwin-update.log";
        ExitTimeOut = 300;
        EnvironmentVariables = {
          # ~/.nix-profile/bin: pi's and nh's dependencies (node, bun, git) live
          # in the user profile, which a launchd agent does not inherit.
          PATH = "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:${userHome}/.nix-profile/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          # Also not inherited: pi reads its provider config from
          # $XDG_CONFIG_HOME/pi, and this user sets XDG_CONFIG_HOME.
          XDG_CONFIG_HOME = "${userHome}/.config";
        };
      };

      # Each run: fetch, and only when `main` moved *and* the diff is
      # `flake.lock` alone, fast-forward, build, and (if sudo allows) activate.
      # Anything else is reported and never materialized locally: a commit that
      # touches modules, activation scripts, the justfile or CI runs code as
      # this user (and, through sudo, as root), so only a human may apply it.
      # The build comes before the switch on purpose — a commit that evaluates
      # but does not build must never reach activation.
      script = ''
        REPO_DIR="${cfg.repoDir}"
        FLAKE="$REPO_DIR#darwinConfigurations.${cfg.darwinConfigName}"
        GIT=${lib.getExe pkgs.git}
        # Stable, root-owned path so the sudoers rule in docs/deployment.md can
        # name one exact binary; `nh` is in environment.systemPackages
        # (modules/darwin/default.nix). The store path changes on every bump.
        NH=/run/current-system/sw/bin/nh
        NOTIFY=${pkgs.terminal-notifier}/bin/terminal-notifier
        OMP=${ompPackage}/bin/omp
        FIX="$REPO_DIR/scripts/omp-fix.sh"
        BUILD_LOG=/tmp/nix-darwin-build.log
        FIX_LOG=/tmp/nix-darwin-fix.log
        AUTO_SWITCH=${lib.boolToString cfg.autoSwitch}
        AUTO_FIX=${lib.boolToString cfg.autoFix}

        # No tty here: never let git or nh block on a credential prompt.
        export GIT_TERMINAL_PROMPT=0

        notify() {
          "$NOTIFY" -title "$1" -message "$2" >/dev/null 2>&1 || true
        }

        build() {
          "$NH" darwin build "$FLAKE" >"$BUILD_LOG" 2>&1
        }

        # Read-only: `--diagnose` gives omp read/glob/grep/find only and no
        # `--auto-approve`, so a log carrying instructions from fetched sources
        # cannot make this run rewrite the config. See scripts/omp-fix.sh.
        diagnose() {
          [ -x "$FIX" ] || return 1
          OMP_BIN="$OMP" "$FIX" "$BUILD_LOG" "$1" --diagnose >"$FIX_LOG" 2>&1
        }

        cd "$REPO_DIR" || exit 1

        # Only ever act on main. On a feature branch or a detached HEAD the
        # merge would either fail (--ff-only) or fold main into someone's work.
        if [ "$("$GIT" rev-parse --abbrev-ref HEAD)" != "main" ]; then
          exit 0
        fi

        # Modified or staged *tracked* files mean someone is working here. Never
        # pull or switch under them: the rebuild would apply a configuration they
        # never reviewed. Untracked files are ignored — they are common, and git
        # refuses a merge that would overwrite one (which lands in the failure
        # notification below).
        if [ -n "$("$GIT" status --porcelain --untracked-files=no)" ]; then
          notify "❄️ Nix Config Update Skipped" "Uncommitted changes in $REPO_DIR"
          exit 0
        fi

        BEFORE=$("$GIT" rev-parse HEAD)
        # Fetch before merging so the changed-path set is known before any of it
        # exists locally. Explicit refspec: `git fetch origin main` updates
        # FETCH_HEAD, not necessarily refs/remotes/origin/main.
        if ! "$GIT" fetch --quiet origin '+refs/heads/main:refs/remotes/origin/main'; then
          notify "⚠️ Nix Config Update Failed" "git fetch failed in $REPO_DIR"
          exit 1
        fi
        REMOTE=$("$GIT" rev-parse refs/remotes/origin/main)

        # Quiet no-op: the common case is that nothing moved.
        if [ "$BEFORE" = "$REMOTE" ]; then
          exit 0
        fi

        REV=$("$GIT" rev-parse --short "$REMOTE")
        NON_LOCK=$("$GIT" diff --name-only "$BEFORE" "$REMOTE" | grep -vx 'flake.lock' || true)
        if [ -n "$NON_LOCK" ]; then
          COUNT=$(printf '%s\n' "$NON_LOCK" | wc -l | tr -d ' ')
          notify "❄️ Nix Config Update Needs Review" "main moved to $REV with $COUNT non-lockfile change(s). Review it, then run 'just switch'."
          exit 0
        fi

        # --ff-only: a diverged local main is a human problem, not something a
        # timer should paper over with a merge or a rebase.
        if ! "$GIT" merge --ff-only --quiet "$REMOTE"; then
          notify "⚠️ Nix Config Update Failed" "could not fast-forward to $REV in $REPO_DIR (diverged branch?) See /tmp/nix-darwin-update.log"
          exit 1
        fi
        if [ "$("$GIT" rev-parse HEAD)" != "$REMOTE" ]; then
          notify "⚠️ Nix Config Update Failed" "HEAD did not move to $REV"
          exit 1
        fi

        if [ "$AUTO_SWITCH" != "true" ]; then
          notify "❄️ Nix Config Updated" "Lockfile bump to $REV applied. Run 'just switch' to activate it."
          exit 0
        fi

        if ! build; then
          notify "🛠️ Nix Config Build Failed" "main is at $REV and does not build."
          if [ "$AUTO_FIX" = "true" ] && diagnose build; then
            notify "🔎 Nix Config Diagnosis" "omp diagnosed the $REV build failure and made no changes. See $FIX_LOG"
          fi
          exit 1
        fi

        # Activation needs root, and a launchd agent has no terminal for Touch
        # ID/YubiKey. `sudo -n` fails immediately instead of blocking on a
        # password prompt nobody can answer.
        if ! /usr/bin/sudo -n true 2>/dev/null; then
          notify "❄️ Nix Config Built" "Built $REV, but sudo needs a terminal. Run 'just switch' to apply it."
          exit 0
        fi

        if /usr/bin/sudo -n "$NH" darwin switch "$FLAKE" >"$BUILD_LOG" 2>&1; then
          notify "✅ Nix Config Auto-Applied" "Built and activated $REV."
        else
          notify "⚠️ Nix Config Switch Failed" "Built $REV but activation failed."
          if [ "$AUTO_FIX" = "true" ] && diagnose switch; then
            notify "🔎 Nix Config Diagnosis" "omp diagnosed the $REV activation failure and made no changes. See $FIX_LOG"
          fi
          exit 1
        fi
      '';
    };
  };
}
