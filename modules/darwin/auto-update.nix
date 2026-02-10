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
      description = "Enable automatic Nix config update notifications";
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
        ExitTimeOut = 60;

        EnvironmentVariables = {
          PATH = "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        };
      };

      script = ''
        echo "--- Check Started: $(date) ---"

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

        # Notify user to manually run just switch
        # Use terminal-notifier if available for persistent notification (0 = never timeout)
        if command -v terminal-notifier >/dev/null 2>&1; then
          terminal-notifier -title "❄️ Nix Update Available" -message "Updates available. Click to open Terminal and run: just switch" -contentImage "${repoDir}/assets/nix-logo.png" -timeout 0 -execute "open -a Terminal"
        else
          /usr/bin/osascript -e 'display notification "Updates available. Run: just switch" with title "❄️ Nix Update Available"'
        fi

        echo "--- Check Finished: $(date) ---"
      '';
    };
  };
}
