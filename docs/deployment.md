# Deployment

This document covers all deployment workflows for both the Darwin (`endor`) and
NixOS (`coruscant`) hosts.

## Darwin (macOS)

### Apply configuration changes

```bash
just switch
# or explicitly:
just switch HOST=endor
```

Requires Homebrew. If Homebrew is not installed, `just switch` installs it
automatically.

### Preview changes without applying

```bash
just build
just diff     # shows nvd diff between current and new system
```

### Validate (flake check + dry build)

```bash
just check
```

### Rollback

```bash
just rollback
```

### View generations

```bash
just generations
```

---

## NixOS (Raspberry Pi — `coruscant`)

### Deploy to default host (`coruscant.local`)

```bash
just nixos-deploy
```

### Deploy to an explicit IP

```bash
just nixos-deploy 192.168.1.50
```

### Deploy to an explicit hostname / Tailscale address

```bash
TARGET=coruscant.tailnet-name.ts.net just nixos-deploy
```

Under the hood this runs:

```bash
nix run nixpkgs#nixos-rebuild -- switch \
  --flake .#coruscant \
  --target-host root@<TARGET> \
  --build-host root@<TARGET> \
  --elevate=sudo
```

The build happens **on the Pi** (aarch64-linux native), so no local
cross-compilation or QEMU setup is needed.

### View remote generations

```bash
just nixos-generations
```

### Rollback remote host

```bash
just nixos-rollback
```

---

## Initial Provisioning (NixOS)

See [docs/nixos.md](nixos.md) for the full provisioning walkthrough.
Quick reference:

```bash
# 1. Prepare age key for secrets
mkdir -p nixos-files/var/lib/sops-nix
cp ~/.config/sops/age/keys.txt nixos-files/var/lib/sops-nix/key.txt

# 2. Boot Pi from installer SD card, then:
just nixos-init                  # default: coruscant-installer.local
just nixos-init 192.168.1.50     # explicit IP
```

---

## OCI VPS (`dathomir`)

The `Build and Deploy OCI Image` GitHub Actions workflow builds
`.#packages.aarch64-linux.vps-image`, uploads the resulting `nixos.qcow2` as a
short-lived workflow artifact, then runs OpenTofu from `infra/` against Oracle
Cloud Infrastructure.

Manual dry-run:

```bash
gh workflow run deploy-oci.yml -f apply=false
```

Manual deploy:

```bash
gh workflow run deploy-oci.yml -f apply=true
```

Pushes to `main` that touch the OCI image, host, or `infra/` paths deploy after
the plan job succeeds. The apply job uses the `oci-production` GitHub
environment, so configure any required reviewers there.

GitHub Actions decrypts `secrets/oci.yaml` in CI with a single `SOPS_AGE_KEY`
repository secret. See
[docs/secrets.md](secrets.md#github-actions-secrets-for-oci-deploy).

---

## SD Card Image

### Build via GitHub Actions (recommended)

```bash
just nixos-build-ci
# Image saved to result-sd-ci/
```

### Build locally

```bash
nix build .#nixosConfigurations.coruscant-sd-image.config.system.build.sdImage
```

### Flash to SD card

```bash
just nixos-flash /dev/sdX
```

---

## Updating Flake Inputs

```bash
just update                     # update all inputs
just update-input nixpkgs       # update a single input
```

After updating, deploy to both hosts:

```bash
just switch
just nixos-deploy
```

---

## Auto-updates

### Darwin

The launchd auto-update service (`services.nix-config-auto-update`) is defined
in `modules/darwin/auto-update.nix` but is **currently disabled** in
`modules/darwin/default.nix` (`enable = false`). For a manual update check, use
`just check-updates`, which runs `scripts/check-for-updates.sh` to pull
`flake.lock` changes and notify you.

```bash
just check-updates         # manual check for flake.lock updates
just auto-update-status    # view the (disabled) service status
```

### NixOS (coruscant)

`system.autoUpgrade` is enabled in `modules/nixos/common.nix`. The host
rebuilds and applies its local flake checkout automatically (it does not fetch
new commits from GitHub — push updates by running `just nixos-deploy` or
rsync-ing the flake to the host first).

---

## Secrets

See [docs/secrets.md](secrets.md) for the complete secrets workflow including
creating, editing, rotating, and backing up secrets.

---

## Garbage Collection

```bash
just clean          # remove generations older than 30 days
just clean-full     # remove all old generations + optimise store
```

On NixOS, garbage collection runs automatically every week
(`nix.gc` in `modules/nixos/common.nix`).
