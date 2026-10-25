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

`switch` runs the build through `tee` and passes `--no-nom` to `nh`: the log is
captured for the failure path, and plain streaming build logs also sidestep
nix-output-monitor's TUI, which renders poorly on a pipe and can leave the
terminal in synchronized-output mode (no visible output) if it dies mid-build.

### When a switch fails

If the build/activation fails, the recipe prints the failure and pipes the log
into `pi` (`pi -p --no-session --approve @<log> ...`) for automated diagnosis
and fixing. Pi edits the repo to address the root cause but does not re-run the
switch itself — re-run `just switch` after it reports back. The helper is
`scripts/pi-fix.sh`, and the daily auto-update agent calls the same script.

- `PI_FIX=0 just switch` — skip the auto-fix; the log path is printed so you can
  inspect it yourself.
- Interrupts (`Ctrl-C`) exit 130 and a signal-killed build (e.g. 134/SIGABRT)
  exits with that status *without* calling pi — those are not config errors.
- The build log is a temp file (path printed on failure) and is kept, so it can
  be read after the run.

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

`just nixos-deploy` builds on **dathomir** first, then copies and activates on the
target. In two steps it runs:

```bash
# step 1 - build on dathomir (aarch64-linux native) - `just nixos-remote-build`
nix run nixpkgs#nixos-rebuild -- build \
  --flake .#coruscant --target-host root@<TARGET> --build-host root@dathomir-1

# step 2 - copy the closure to the target and activate it
nix run nixpkgs#nixos-rebuild -- switch \
  --flake .#coruscant --target-host root@<TARGET> --build-host root@dathomir-1
```

**Builds do not run on the Pi** (see `BUILD_HOST` in the `justfile`). A Pi 4
compiling a system on a USB root takes ~25 minutes cold, and that load is what
hard-stopped `coruscant` on 2026-10-23; on dathomir the same build takes ~18
seconds once its store is warm. The two steps are also kept apart so the target
is not restarting all its services (HA, zigbee2mqtt, …) while it is still
compiling.

```bash
BUILD_HOST=local just nixos-deploy   # build on the target itself (old behaviour)
BUILD_HOST=other-arm-host just nixos-deploy
```

A cold dathomir store costs ~25 minutes the first time; after that only the
changed derivations are rebuilt. Do **not** run a destructive `nix-collect-garbage`
on dathomir without a binary cache in place — it is the build cache.

### Pre-build without activating

The build half has its own recipe, which is useful for warming the build host's
store ahead of a deploy at a quiet moment:

```bash
just nixos-remote-build             # builds coruscant on dathomir by default
just nixos-remote-build 10.0.0.2    # other target, same build host
```

A later `just nixos-deploy` then only has to copy and activate, since the store
paths are already built.

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
# 1. Prepare the host's age key (one key per host — see docs/secrets.md)
mkdir -p nixos-files/var/lib/sops-nix
cp ~/.config/sops/age/host-keys/coruscant.txt nixos-files/var/lib/sops-nix/key.txt

# 2. Boot Pi from installer SD card, then:
just nixos-init                  # default: coruscant-installer.local
just nixos-init 192.168.1.50     # explicit IP
```

---

## OCI VPS (`dathomir`)

The `deploy-oci.yml` GitHub Actions workflow drives OpenTofu from `infra/`
against Oracle Cloud Infrastructure. It no longer builds an image: an Always Free
tenancy has `custom-image-count = 0`, so the instance boots an Oracle **platform
image** and is converted to NixOS in place by an operator-run step — CI has no
path into the instance, which is Tailscale-only. See
[docs/dathomir.md](dathomir.md).

Manual dry-run:

```bash
gh workflow run deploy-oci.yml -f apply=false
```

Manual deploy:

```bash
gh workflow run deploy-oci.yml -f apply=true
```

A1 free-tier capacity is scarce, so an apply from CI often fails with
`500-InternalError, Out of host capacity`. Retry locally instead, where the
fault-domain rotation runs:

```bash
just -f infra/justfile apply-retry
just dathomir-convert            # platform image -> NixOS, over the tailnet
```

> **Paused (2025-08-14):** auto-run on push is disabled, so pushes to `main` no longer
> trigger a build. Only manual runs via the Actions tab or `gh workflow run` work
> until re-enabled (see the note in `deploy-oci.yml`).

The apply job uses the `oci-production` GitHub environment, so configure any
required reviewers there.

GitHub Actions decrypts `secrets/oci.yaml` in CI with a single `SOPS_AGE_KEY`
repository secret. See
[docs/secrets.md](secrets.md#github-actions-secrets-for-oci-deploy).

---

## SD Card Image

### Build via GitHub Actions (recommended)

```bash
just nixos-build-ci
# Image saved to result-sd-ci-coruscant/
```

The workflow runs on a native arm64 runner (no QEMU emulation) and can build
any host with an `-sd-image` variant via `NHOST=<host>`. Artifacts are named
with the commit SHA they were built from, and include `sha256sums.txt`.

### Build locally

```bash
nix build .#nixosConfigurations.coruscant-sd-image.config.system.build.sdImage
```

### Flash to SD card

```bash
just nixos-flash /dev/sdX
# or for a specific host:
NHOST=<host> just nixos-flash /dev/sdX
```

`nixos-flash` validates the whole-disk target, prompts before unmounting/overwriting,
and verifies the full image against the device after flashing.

---

## CI/CD (GitHub Actions)

`.github/workflows/` runs several workflows:

| Workflow | When | What it does |
|----------|------|--------------|
| `flake-check.yml` | Push/PR to `main`/`master` | `nix flake show` smoke check + nixConfig/nix-caches sync guard, `nix flake check --all-systems --no-build` (all-systems eval) plus a native `nix flake check` on Linux, eval-only darwin smoke (saves macOS runner minutes; real builds happen via `just build`) |
| `build-sd-image.yml` | Manual dispatch or push touching ARM-Pi paths | Builds a host's `-sd-image` on a native arm64 runner (see [docs/nixos.md](nixos.md)) |
| `deploy-oci.yml` | Manual dispatch, or push touching OCI/`infra/` paths | Builds the OCI image, plans, then applies to the `oci-production` environment (see [docs/dathomir.md](dathomir.md)) |
| `dependabot-auto-merge.yml` | On Dependabot PRs | Auto-merges (squash) Dependabot PRs once their checks pass |

`dependabot.yml` enables weekly dependency updates for **GitHub Actions** and
**Nix flake inputs** (grouped together, labeled `dependencies`). Merged Dependabot
PRs to `main` may trigger the OCI deploy (if `flake.lock` changed) and are
auto-merged; the `oci-production` environment can require reviewers before apply.

## Updating Flake Inputs

```bash
just update                     # update all inputs
just update-input nixpkgs       # update a single input
```

Both commit the updated `flake.lock` (`--commit-lock-file`), so updating leaves
a commit on your branch rather than a dirty lockfile.

After updating, deploy to both hosts:

```bash
just switch
just nixos-deploy
```

---

## Auto-updates

Two layers, deliberately separate. **CI moves `flake.lock`; hosts only consume
`main`.** No host runs `nix flake update` — the one time the lock was bumped
locally it was reverted within the hour.

### CI (the lockfile)

Dependabot's `nix` ecosystem (`.github/dependabot.yml`) opens one grouped
`chore(flake): bump the flake-input-updates group…` PR every Monday 08:00
Pacific. `.github/workflows/dependabot-auto-merge.yml` squash-merges it once the
`Main` ruleset's required checks pass, so a bump that fails `smoke`,
`linux-check` or `darwin-check` cannot reach `main`.

`flake-check.yml` also runs `darwin-build`, which realises
`darwinConfigurations.endor.system` instead of only evaluating it. That is the
only check that catches the failure an input bump actually produces — a package
that no longer builds — so watch its runtime and then add it to the `Main`
ruleset's required checks.

Manual equivalents: `just update` and `just update-input <input>`.

### Darwin

`services.nix-config-auto-update` (`modules/darwin/auto-update.nix`, enabled in
`modules/darwin/default.nix`) runs daily at 10:00 as a launchd **user** agent:

1. exits immediately when the working tree is dirty, so local work is never
   pulled or switched out from under you;
2. `git pull --ff-only origin main`, then exits quietly when `main` did not move;
3. otherwise `nh darwin build` — a commit that evaluates but does not build is
   reported and never activated;
4. then `sudo -n nh darwin switch`;
5. if either stage fails, the log goes to `pi` via `scripts/pi-fix.sh` — the same
   helper `just switch` uses — which rebuilds and re-switches once. The repair is
   left uncommitted on purpose, so every later run skips this repository until
   you review it. `services.nix-config-auto-update.autoFix = false` turns it off.

`sudo -n` is deliberate: the agent has no terminal, so Touch ID and YubiKey
cannot answer a password prompt. Without a sudoers rule step 4 fails at once,
the agent still builds and notifies, and `just switch` finishes the job. To let
it activate unattended, put `nh` on a stable path and whitelist that path:

```nix
environment.systemPackages = [ pkgs.nh ];
security.sudo.extraConfig = ''
  <user> ALL=(root) NOPASSWD: /run/current-system/sw/bin/nh
'';
```

That grants passwordless root activation from your account — only worth it if
full auto-apply is what you want.

```bash
just auto-update-status                  # launchd service status
launchctl start nix-config-auto-update   # trigger a run now
tail -f /tmp/nix-darwin-update.log       # what the agent did
just check-updates                       # manual flake.lock check
```

### NixOS (coruscant)

`system.autoUpgrade` is **disabled** in `modules/nixos/common.nix` — the old
flake-relative flag could not build on the host, so updates were silently
failing nightly. Deploy intentionally: `just nixos-deploy` (or rsync the flake
and run `nixos-rebuild switch` manually).

If it is ever enabled, point `flake` at a URL (`github:adace123/nixos-config-v2`,
never `inputs.self` — that resolves to the store copy of the config being
evaluated and so never sees a newer commit), keep `flags = [ "--refresh" ]`,
add jitter via `randomizedDelaySec`, and wire `onFailure` to a notification
*before* turning it on: silent failure is that module's dominant mode.

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
