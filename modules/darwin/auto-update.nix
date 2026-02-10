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
        description = "Enable automatic Nix config update notifications";
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
    };
  };

  config = lib.mkIf config.services.nix-config-auto-update.enable {
    launchd.user.agents.nix-config-auto-update = {
      serviceConfig = {
        Label = "org.nix-community.darwin.auto-update";
        # Runs daily at configured time
        StartCalendarInterval = [
          {
            Hour = config.services.nix-config-auto-update.hour;
            Minute = config.services.nix-config-auto-update.minute;
          }
        ];

        StandardErrorPath = "/tmp/nix-darwin-update.log";
        StandardOutPath = "/tmp/nix-darwin-update.log";

        # Ensures the process doesn't hang forever
        ExitTimeOut = 60;

        EnvironmentVariables = {
          PATH = "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        };
      };

      script = ''
        set -e

        echo "--- Check Started: $(date) ---"

        cd ${repoDir} || {
          echo "ERROR: Failed to change to repo directory: ${repoDir}"
          exit 1
        }

        # Run the check-for-updates.sh script which will detect updates and notify user
        # but won't prompt for user input or run just switch automatically
        ${pkgs.bash}/bin/bash ./scripts/check-for-updates.sh --auto

        echo "--- Check Finished: $(date) ---"
      '';
    };
  };
}
