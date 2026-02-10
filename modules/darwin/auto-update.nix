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

        # Function to retry a command with backoff
        retry_with_backoff() {
          local max_attempts=$1
          local cmd="''${@:2}"
          local attempt=1
          
          while [ $attempt -le $max_attempts ]; do
            if eval "$cmd"; then
              return 0
            fi
            
            if [ $attempt -eq $max_attempts ]; then
              echo "Command failed after $max_attempts attempts: $cmd"
              return 1
            fi
            
            local delay=$((attempt * 5))
            echo "Attempt $attempt failed. Retrying in ''${delay}s..."
            sleep $delay
            attempt=$((attempt + 1))
          done
        }

        # Wait for network availability with retry
        if ! retry_with_backoff 3 "/usr/bin/curl -s --head --request GET http://www.google.com | grep -q '200 OK'"; then
          echo "ERROR: No internet connection after retries"
          exit 1
        fi
        echo "Internet connection confirmed"

        cd ${repoDir} || {
          echo "ERROR: Failed to change to repo directory: ${repoDir}"
          exit 1
        }

        # Check if this is a git repo
        if [ ! -d .git ]; then
          echo "ERROR: Not a git repository"
          exit 1
        fi

        # Fetch updates from origin with retry
        if ! retry_with_backoff 3 "${pkgs.git}/bin/git fetch origin main"; then
          echo "ERROR: Failed to fetch from origin/main after retries"
          
          # Notify about the error
          if command -v terminal-notifier >/dev/null 2>&1; then
            terminal-notifier -title "❄️ Nix Update Error" -message "Failed to check for updates. Check logs at /tmp/nix-darwin-update.log" -timeout 0
          else
            /usr/bin/osascript -e 'display notification "Failed to check for updates" with title "❄️ Nix Update Error"'
          fi
          
          exit 1
        fi

        # Get commit hashes
        LOCAL=$(${pkgs.git}/bin/git rev-parse HEAD) || {
          echo "ERROR: Failed to get local HEAD"
          exit 1
        }

        REMOTE=$(${pkgs.git}/bin/git rev-parse origin/main) || {
          echo "ERROR: Failed to get remote HEAD"
          exit 1
        }

        if [ "$LOCAL" = "$REMOTE" ]; then
          echo "Already up to date"
          exit 0
        fi

        echo "Remote changes detected: ''${LOCAL:0:7} -> ''${REMOTE:0:7}"

        # Check if flake.lock changed between commits
        if ! ${pkgs.git}/bin/git diff --name-only "$LOCAL" "$REMOTE" | grep -q "flake.lock"; then
          echo "No changes to flake.lock"
          exit 0
        fi

        echo "✅ flake.lock updates available!"

        # Notify user to manually run just switch
        if command -v terminal-notifier >/dev/null 2>&1; then
          terminal-notifier -title "❄️ Nix Update Available" -message "Updates available. Click to open Terminal and run: just switch" -timeout 0 -execute "open -a Terminal"
        else
          /usr/bin/osascript -e 'display notification "Updates available. Run: just switch" with title "❄️ Nix Update Available"'
        fi

        echo "--- Check Finished: $(date) ---"
      '';
    };
  };
}
