{
  description = "macOS system configuration with nix-darwin, Raspberry Pi, and VPS NixOS";

  # Binary caches for building flake outputs
  # NOTE: nixConfig must stay a literal set (nix reads it without evaluating
  # imports), so this duplicates nix-caches.nix — keep both in sync. The
  # NixOS/home modules import nix-caches.nix directly.
  nixConfig = {
    extra-substituters = [
      "https://cache.numtide.com"
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
    };

    # The herdr kanban board plugin. It has its own repo because the Nix
    # packaging is *about the plugin* — it enumerates the plugin's modules and
    # asserts nothing ships unimported — so it belongs next to the code it
    # guards, where that repo's CI can run it. Consumed as a home-manager module
    # in modules/home/ai/herdr/herdr.nix; this repo keeps the keybindings and
    # the config with our workspace codes and model names.
    herdr-kanban = {
      url = "github:adace123/herdr-kanban";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # OmniWM's own flake, not the module home-manager ships. OmniWM rejects any
    # settings.toml that is not its complete schema, and the stock module writes
    # exactly what you hand it — so a partial `programs.omniwm.settings` file is
    # silently ignored at runtime. This one merges our settings over a full
    # settings-defaults.toml regenerated from the packaged version, merges
    # hotkeys per id, and fails evaluation on an id OmniWM does not know. It also
    # packages OmniWM itself, so package and defaults template always agree.
    # Consumed in modules/home/omniwm.nix. nixpkgs follows ours so the lock keeps
    # a single nixpkgs.
    omniwm = {
      url = "github:mst-mkt/omniwm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pi itself comes from the official flake, not llm-agents: it is upstream's
    # own build (nix/package.nix), so it tracks the same release the `pi update`
    # channel does. `main` is deliberate — upstream also keeps a `stable` branch
    # pinned to the last release. nixpkgs follows ours so the lock keeps a
    # single nixpkgs (upstream's own pin stays lower in the lock but is only
    # used for its x86_64-darwin package, which this flake never evaluates).
    # OMP (the coding agent; this machine runs the brew binary today). The
    # upstream flake's homeManagerModules.default owns ~/.omp/agent/config.yml
    # declaratively — consumed in modules/home/ai/omp.nix so `just switch`
    # writes the model roles and advisor config below. nixpkgs follows ours so
    # the lock keeps a single nixpkgs.
    omp = {
      url = "github:can1357/oh-my-pi/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pi = {
      url = "github:earendil-works/pi/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Plain source input (no flake.nix in the repo) — skills are referenced
    # from inputs.mattpocock-skills so they stay in sync with upstream.
    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    zed-extensions = {
      url = "github:DuskSystems/nix-zed-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      flake = flake-parts.lib.mkFlake { inherit inputs; } {
        systems = [
          "aarch64-darwin"
          "aarch64-linux"
          "x86_64-linux"
        ];

        imports = [
          ./flake-parts/darwin.nix
          ./flake-parts/infra.nix
          ./flake-parts/pre-commit.nix
          ./flake-parts/nixos.nix
        ];
      };
    in
    # No `packages.aarch64-linux.vps-image` any more: an Always Free OCI tenancy
    # has custom-image-count = 0, so the built qcow2 could never be imported as a
    # custom image. dathomir boots an Oracle platform image and is converted to
    # NixOS in place — see docs/dathomir.md.
    flake;
}
