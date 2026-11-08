{
  lib,
  pkgs,
  config,
  ...
}:
let
  caches = import ../../nix-caches.nix;

  # Determinate Nix's tarball cache (the bare git repo it unpacks flake inputs
  # into) grows one pack file per fetched input and never prunes itself. libgit2
  # opens a descriptor per cached pack while it walks the object database, so a
  # large cache exhausts the process limit and `nix flake update` dies with
  #   writing packfile: -1, failed to open directory '.../refs/': Too many open files
  # It is a pure download cache: deleting it only costs a re-fetch. This prunes
  # it past a pack-count threshold (2 descriptors per pack) and clears the
  # `pack_git2_*.lock` files interrupted libgit2 writes leave behind.
  pruneCache = pkgs.writeShellApplication {
    name = "nix-tarball-cache-prune";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      cache="''${XDG_CACHE_HOME:-$HOME/.cache}/nix/tarball-cache-v2"
      pack_dir="$cache/objects/pack"
      limit=2000

      [ -d "$pack_dir" ] || exit 0

      packs=$(find "$pack_dir" -maxdepth 1 -name '*.pack' | wc -l | tr -d ' ')

      # A nix client that is fetching or building may hold the cache open;
      # deleting underneath it surfaces as a transient fetcher error. Retry on
      # the next run instead. Process names are matched with ps: pgrep's user
      # filter is broken on Darwin (BSD pgrep matches nothing, GNU pgrep's -U
      # drops every process), and the daemon's root workers never use this
      # cache. comm is a bare name for user processes and a full path for
      # launchd daemons, hence both forms.
      me=$(id -un)
      if /bin/ps -axo user=,comm= | /usr/bin/awk -v me="$me" '$1 == me && ($2 == "nix" || $2 ~ /\/nix$/) { found = 1 } END { exit !found }'; then
        echo "packs=$packs limit=$limit nix client running, skipped"
        exit 0
      fi

      if [ "$packs" -gt "$limit" ]; then
        rm -rf "$cache"
        echo "packs=$packs limit=$limit pruned"
      else
        find "$pack_dir" -maxdepth 1 -name '*.lock' -delete 2>/dev/null || true
        echo "packs=$packs limit=$limit ok"
      fi
    '';
  };
in
{
  # Written to ~/.config/nix/nix.conf since nix-darwin has nix.enable = false
  # (using Determinate Nix installer instead).
  # Single source of truth: nix-caches.nix (also used by flake.nix `nixConfig`
  # and modules/nixos/common.nix).
  xdg.configFile."nix/nix.conf".text = ''
    experimental-features = nix-command flakes
    max-jobs = auto
    cores = 0
    extra-substituters = ${lib.concatStringsSep " " caches.extra-substituters}
    extra-trusted-public-keys = ${lib.concatStringsSep " " caches.extra-trusted-public-keys}
  '';

  # Every 6 hours while awake; launchd catches up after a wake. The job is a
  # few stat calls when the cache is small, so the cadence is cheap.
  launchd.agents.nix-tarball-cache-prune = {
    enable = true;

    config = {
      ProgramArguments = [ "${pruneCache}/bin/nix-tarball-cache-prune" ];

      EnvironmentVariables.HOME = config.home.homeDirectory;

      StartInterval = 6 * 60 * 60;
      RunAtLoad = true;
      ProcessType = "Background";
      LowPriorityIO = true;

      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/nix-tarball-cache-prune.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/nix-tarball-cache-prune.log";
    };
  };
}
