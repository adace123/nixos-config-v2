{ inputs, ... }:
let
  hosts = import ../hosts;
  host = hosts.endor;
in
{
  flake.darwinConfigurations = {
    "${host.hostName}" = inputs.darwin.lib.darwinSystem {
      inherit (host) system;
      specialArgs = { inherit inputs host; };
      modules = [
        ../modules/darwin
        inputs.sops-nix.darwinModules.sops
        inputs.home-manager.darwinModules.home-manager
        {
          nixpkgs.overlays = [
            inputs.zed-extensions.overlays.default
            # Upstream nixpkgs#6b5e5b7 (2026-08-13) pinned a stale hash for the
            # nanoemoji v0.16.0 GitHub release archive (GitHub re-rolled it),
            # so jetbrains-mono → gftools → nanoemoji fails with a fixed-output
            # hash mismatch. nixpkgs master has already updated the hash; this
            # overlay mirrors it and self-disables once the lock moves past the
            # broken rev (guarded on the stale hash value).
            (_final: prev: {
              python313 = prev.python313.override {
                packageOverrides = _pfinal: pprev: {
                  nanoemoji = pprev.nanoemoji.overrideAttrs (old: {
                    src =
                      if old.src.hash == "sha256-gM53wlQSV/X7rDND6P7/fKpX0M28RDnWkGGOHQ+SK+g=" then
                        old.src.override {
                          hash = "sha256-FysyKC01XBnRiur5RR9fcsTxQqE8x0JJHSoe3q6JtKc=";
                        }
                      else
                        old.src;
                  });
                };
              };
            })
          ];

          nixpkgs.config.allowBroken = true;

          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "bak";
            # Hermes (and other tools) atomic-replace their config symlink and
            # leave a read-only .bak (0444). Home-manager's backup step is
            # `mv target target.bak` (no -f); BSD mv prompts on a read-only
            # destination and hangs activation. overwriteBackup makes it `rm`
            # the stale .bak first, so the mv is a clean rename.
            overwriteBackup = true;
            sharedModules = [
              inputs.sops-nix.homeManagerModules.sops
              inputs.zed-extensions.homeManagerModules.default
            ];
            users.${host.user.name} = {
              imports = [ ../modules/home ];
              home = {
                username = host.user.name;
                homeDirectory = host.user.homeDirectory;
              };
            };
            extraSpecialArgs = { inherit inputs host; };
          };
        }
      ];
    };

  };
}
