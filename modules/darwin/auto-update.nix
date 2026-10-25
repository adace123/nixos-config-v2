{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:

let
  userHome = config.users.users.${config.system.primaryUser}.home;
  cfg = config.services.nix-config-auto-update;
  piPackage = inputs.pi.packages.${pkgs.stdenv.hostPlatform.system}.pi;

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
          Build and activate new commits automatically. The build always runs
          when `main` moves; activation then needs non-interactive root, which a
          launchd agent only has if sudo is configured for it. Without that the
          build is still reported and the switch is left to `just switch`.
        '';
      };

      autoFix = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Hand a failed build or activation to `pi` (see `scripts/pi-fix.sh`),
          then rebuild and re-switch once. The repair is left uncommitted, which
          also makes every later run skip this repository until it is reviewed.
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

      # Each run: pull, and only if `main` actually moved, build and (if sudo
      # allows) activate. The build comes before the switch on purpose — a commit
      # that evaluates but does not build must never reach activation, and the
      # review happens upstream in CI, not here.
      script = ''
        REPO_DIR="${cfg.repoDir}"
        FLAKE="$REPO_DIR#darwinConfigurations.${cfg.darwinConfigName}"
        GIT=${lib.getExe pkgs.git}
        NH=${lib.getExe pkgs.nh}
        NOTIFY=${pkgs.terminal-notifier}/bin/terminal-notifier
        PI=${piPackage}/bin/pi
        FIX="$REPO_DIR/scripts/pi-fix.sh"
        BUILD_LOG=/tmp/nix-darwin-build.log
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

        # pi gets one attempt per stage. A second failure is reported instead of
        # retried: looping on the same commit burns tokens and tells nobody.
        repair() {
          [ -x "$FIX" ] || return 1
          PI_BIN="$PI" "$FIX" "$BUILD_LOG" "$1"
        }

        cd "$REPO_DIR" || exit 1

        # Only ever act on main. On a feature branch or a detached HEAD the pull
        # would either fail (--ff-only) or fold main into someone's work.
        if [ "$("$GIT" rev-parse --abbrev-ref HEAD)" != "main" ]; then
          exit 0
        fi

        # Modified or staged *tracked* files mean someone is working here. Never
        # pull or switch under them: the rebuild would apply a configuration they
        # never reviewed. Untracked files are ignored — they are common, and git
        # refuses a pull that would overwrite one (which lands in the failure
        # notification below).
        if [ -n "$("$GIT" status --porcelain --untracked-files=no)" ]; then
          notify "❄️ Nix Config Update Skipped" "Uncommitted changes in $REPO_DIR"
          exit 0
        fi

        BEFORE=$("$GIT" rev-parse HEAD)
        # --ff-only: a diverged local main is a human problem, not something a
        # timer should paper over with a merge or a rebase.
        if ! "$GIT" pull --ff-only --quiet origin main; then
          notify "⚠️ Nix Config Update Failed" "git pull failed in $REPO_DIR (diverged branch?) See /tmp/nix-darwin-update.log"
          exit 1
        fi
        AFTER=$("$GIT" rev-parse HEAD)

        # Quiet no-op: the common case is that nothing moved.
        if [ "$BEFORE" = "$AFTER" ]; then
          exit 0
        fi

        REV=$("$GIT" rev-parse --short HEAD)

        if [ "$AUTO_SWITCH" != "true" ]; then
          notify "❄️ Nix Config Updated" "New commits on main ($REV). Run 'just switch' to apply them."
          exit 0
        fi

        if ! build; then
          notify "🛠️ Nix Config Build Failed" "main is at $REV and does not build. Asking pi to repair it."
          if [ "$AUTO_FIX" = "true" ] && repair build && build; then
            notify "🛠️ Nix Config Repaired" "pi fixed the build at $REV. Changes are uncommitted — review with 'git diff' and commit."
          else
            notify "⚠️ Nix Config Build Failed" "main is at $REV and does not build. See $BUILD_LOG"
            exit 1
          fi
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
        elif [ "$AUTO_FIX" = "true" ] && repair switch && /usr/bin/sudo -n "$NH" darwin switch "$FLAKE" >"$BUILD_LOG" 2>&1; then
          notify "🛠️ Nix Config Repaired" "pi fixed the activation failure at $REV and it is now applied. Review with 'git diff' and commit."
        else
          notify "⚠️ Nix Config Switch Failed" "Built $REV but activation failed. See $BUILD_LOG"
          exit 1
        fi
      '';
    };
  };
}
