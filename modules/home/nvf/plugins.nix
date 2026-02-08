{pkgs, ...}: {
  # Custom plugin definitions
  # This module exports customPlugins via _module.args for use by other modules

  _module.args.customPlugins = {
    telescope-tabs = pkgs.vimUtils.buildVimPlugin {
      name = "telescope-tabs";
      doCheck = false;
      src = pkgs.fetchFromGitHub {
        owner = "LukasPietzschmann";
        repo = "telescope-tabs";
        rev = "0a678eefcb71ebe5cb0876aa71dd2e2583d27fd3";
        hash = "sha256-IvxZVHPtApnzUXIQzklT2C2kAxgtAkBUq3GNxwgPdPY=";
      };
    };
  };
}
