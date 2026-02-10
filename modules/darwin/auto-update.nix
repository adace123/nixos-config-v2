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
    services.nix-config-auto-update = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable automatic Nix config updates";
    };
  };

  config = lib.mkIf config.services.nix-config-auto-update {
    launchd.user.agents.nix-config-auto-update = {
      serviceConfig = {
        Label = "org.nix-community.darwin.auto-update";
        # Runs every day at 10:00 AM
        StartCalendarInterval = [
          {
            Hour = 10;
            Minute = 0;
          }
        ];

        StandardErrorPath = "/tmp/nix-darwin-update.log";
        StandardOutPath = "/tmp/nix-darwin-update.log";

        # Ensures the process doesn't hang forever
        ExitTimeOut = 600;

        EnvironmentVariables = {
          PATH = "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        };
      };

      script = ''
        echo "--- Update Started: $(date) ---"

        # Check if lid is closed (skip if closed - Touch ID won't work)
        if command -v ioreg >/dev/null 2>&1; then
          lid_closed=$(ioreg -r -k AppleClamshellState -d 4 | grep AppleClamshellState | head -1 | grep -c "Yes" || echo "0")
          if [ "$lid_closed" -eq 1 ]; then
            echo "Lid is closed, skipping update (Touch ID unavailable)"
            exit 0
          fi
        fi

        # Wait for network availability
        until /usr/bin/curl -s --head --request GET http://www.google.com | grep "200 OK" > /dev/null; do
          echo "Waiting for internet..."
          sleep 30
        done

        cd ${repoDir}

        # Check if there are updates
        ${pkgs.git}/bin/git fetch origin main
        LOCAL=$(${pkgs.git}/bin/git rev-parse HEAD)
        REMOTE=$(${pkgs.git}/bin/git rev-parse origin/main)

        if [ "$LOCAL" = "$REMOTE" ]; then
          echo "Already up to date"
          exit 0
        fi

        echo "Updates available: ''${LOCAL:0:7} -> ''${REMOTE:0:7}"

        # Update flake.lock and rebuild
        /run/current-system/sw/bin/nix flake update --commit-lock-file

        # Run darwin-rebuild (this will prompt for Touch ID if needed)
        if /run/current-system/sw/bin/darwin-rebuild switch --flake .; then
          echo "Update completed successfully"
          /usr/bin/osascript -e 'display notification "Nix-Darwin updated successfully!" with title "❄️ Nix Update"'
        else
          echo "Update FAILED"
          /usr/bin/osascript -e 'display notification "Nix-Darwin update FAILED. Check logs at /tmp/nix-darwin-update.log" with title "❄️ Nix Update Error"'
        fi

        echo "--- Update Finished: $(date) ---"
      '';
    };
  };
}
