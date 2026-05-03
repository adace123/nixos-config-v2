{
  config,
  pkgs,
  lib,
  ...
}:

let
  userHome = config.users.users.aaron.home;
  repoDir = "${userHome}/Projects/personal/nixos-config-v2";

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
        description = "Automatically run `nh darwin switch` when updates are detected";
      };

      darwinConfigName = lib.mkOption {
        type = lib.types.str;
        description = "Name of the darwinConfiguration output in the flake (e.g. the key under flake.darwinConfigurations)";
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
          PATH = "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        };
      };

      script = ''
        cd ${repoDir} || exit 1

        BEFORE=$(git rev-parse HEAD)
        git pull --rebase origin main
        AFTER=$(git rev-parse HEAD)

        if [ "$BEFORE" != "$AFTER" ] && [ "${lib.boolToString config.services.nix-config-auto-update.autoSwitch}" = "true" ]; then
          if ${lib.getExe pkgs.nh} darwin switch ${repoDir}#darwinConfigurations.${config.services.nix-config-auto-update.darwinConfigName}; then
            ${pkgs.terminal-notifier}/bin/terminal-notifier \
              -title "✅ Nix Config Auto-Applied" \
              -message "Applied latest nix-config changes"
          else
            ${pkgs.terminal-notifier}/bin/terminal-notifier \
              -title "⚠️ Nix Config Update Failed" \
              -message "Pulled changes but failed to switch. Run: nh darwin switch ${repoDir}#darwinConfigurations.${config.services.nix-config-auto-update.darwinConfigName}"
            exit 1
          fi
        elif [ "$BEFORE" != "$AFTER" ]; then
          ${pkgs.terminal-notifier}/bin/terminal-notifier \
            -title "❄️ Nix Config Updated" \
            -message "Run 'just switch' to apply changes"
        fi
      '';
    };
  };
}
