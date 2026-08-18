{ config, ... }:
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home = {
    # This value determines the Home Manager release that your configuration is
    # compatible with. This helps avoid breakage when a new Home Manager release
    # introduces backwards incompatible changes.
    stateVersion = "24.05";
    enableNixpkgsReleaseCheck = false;

    # Prepend to PATH.
    sessionPath = [
      "$HOME/.npm-global/bin" # Global npm packages (e.g. @coinbase/coinbase-cli)
    ];

    sessionVariables = {
      DIRENV_LOG_FORMAT = ""; # Hide direnv export output
      EDITOR = "nvim";
      NH_FLAKE = "${config.home.homeDirectory}/Projects/personal/nixos-config-v2"; # Enable nh commands without specifying flake path
    };
  };

  # AI Assistant Selector Script.
  home.file.".local/bin/ai-selector" = {
    source = ../../scripts/ai-selector.sh;
    executable = true;
  };

  xdg.enable = true;
}
