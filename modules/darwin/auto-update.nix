{
  config,
  pkgs,
  lib,
  ...
}:

let
  userHome = config.users.users.aaron.home;
  repoDir = "${userHome}/Projects/personal/nixos-config-v2";
  stateDir = "${userHome}/.local/share";
  serviceName = "nix-config-auto-update";

  # Reference to the external script
  autoUpdateScript = pkgs.writeShellApplication {
    name = serviceName;
    text = builtins.readFile ../../scripts/auto-update.sh;
    runtimeInputs = [
      pkgs.git
      pkgs.coreutils
    ];
  };

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
    launchd.user.agents.${serviceName} = {
      command = "${autoUpdateScript}/bin/${serviceName}";
      serviceConfig = {
        KeepAlive = false;
        RunAtLoad = false;
        WorkingDirectory = repoDir;
        StandardOutPath = "${stateDir}/nix-config-auto-update.stdout.log";
        StandardErrorPath = "${stateDir}/nix-config-auto-update.stderr.log";
        StartCalendarInterval = [
          {
            Hour = 9;
            Minute = 0;
            Weekday = 1;
          } # Monday
          {
            Hour = 9;
            Minute = 0;
            Weekday = 2;
          } # Tuesday
          {
            Hour = 9;
            Minute = 0;
            Weekday = 3;
          } # Wednesday
          {
            Hour = 9;
            Minute = 0;
            Weekday = 4;
          } # Thursday
          {
            Hour = 9;
            Minute = 0;
            Weekday = 5;
          } # Friday
        ];
        EnvironmentVariables = {
          PATH = "${userHome}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin";
        };
      };
    };
  };
}
