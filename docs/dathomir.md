# dathomir — OCI Always-Free VPS

`dathomir` is an aarch64-linux VPS running on
[Oracle Cloud Infrastructure](https://www.oracle.com/cloud/) (OCI) inside the
**Always Free** tier. It is provisioned with OpenTofu from the `infra/`
directory, boots a NixOS **OCI image** built from this flake, and joins your
Tailscale tailnet on first boot. There is **no public IP** — all access goes
through Tailscale.

## Architecture

| Piece | Where |
|-------|-------|
| Host identity (hostname, ssh keys) | `hosts/dathomir/default.nix` |
| NixOS system (OCI image + cloud-init + Tailscale) | `flake-parts/nixos.nix` (inline module) |
| OpenTofu infrastructure (`infra/` dir) | `infra/main.tf`, `providers.tf`, etc. |
| OCI / R2 secrets | `secrets/oci.yaml` |
| Remote state | Cloudflare R2 (`infra/backend.tf`) |

The NixOS configuration is small by design — it mostly enables `oci-image.nix`,
`cloud-init`, and a `tailscale-autoconnect` service that reads an auth key
written by cloud-init. It intentionally does **not** import the home-server
modules (`common.nix`, `home-assistant`, etc.) — `dathomir` is a general-purpose
compute node, not a second home server.

## How the pieces fit

### Flake outputs

- `.#nixosConfigurations.dathomir` — the NixOS system.
- `.#packages.aarch64-linux.vps-image` — builds the bootable OCI `qcow2` image
  the playbook uploads. Requires an aarch64-linux builder (native ARM runner in
  CI; locally you need a Linux builder or `--system aarch64-linux` support).

### `infra/` (OpenTofu)

The `infra/` directory is a self-contained OpenTofu workspace:

| File | Purpose |
|------|---------|
| `providers.tf` | OCI provider config |
| `main.tf` | Instance, SSH keys, cloud-init (writes the Tailscale auth key) |
| `variables.tf` | Always-Free-constrained inputs (shape, OCPUs, memory, AD/fault domain) |
| `backend.tf` | Remote state in R2 |
| `tofu-env.sh` | Decrypts `secrets/oci.yaml` and exports OCI + R2 vars for OpenTofu |
| `terraform.tfvars.example` | Non-secret local config template |
| `justfile` | `just -f infra/justfile <recipe>` — OpenTofu workflow |
| `result/nixos.qcow2` | Symlink to the built OCI image (produced by `build-image`) |

### Remote state (Cloudflare R2)

Terraform/OpenTofu state is stored remotely in the same R2 bucket as the Restic
backups (subkey `infra/terraform.tfstate`). Initialize once with:

```bash
just -f infra/justfile init
```

`init` passes the backend config via credentials from `secrets/oci.yaml`. The
R2 bucket must exist before the first `init` — see the note in `infra/backend.tf`.

## Local (manual) workflow

You normally don't run this by hand — CI deploys on push to `main` (see
below). But when you need to plan, apply, or destroy manually:

```bash
# 1. Build the OCI image -> ./result/nixos.qcow2
just -f infra/justfile build-image

# 2. One-time backend (R2 state) setup
just -f infra/justfile init

# 3. Plan
just -f infra/justfile tf plan

# 4. Apply
just -f infra/justfile tf apply

# 5. Inspect / destroy
just -f infra/justfile tf plan -destroy
just -f infra/justfile destroy
```

Each command runs inside the `infra` dev shell (`nix develop .#infra`) and
decrypts `secrets/oci.yaml` on the fly — the OCI private key is written to a
temp file and cleaned up on exit.

## GitHub Actions deploy

The `deploy-oci.yml` workflow automates the whole lifecycle:

- **Trigger:** manual dispatch, or a push to `main` touching
  `.github/workflows/deploy-oci.yml`, `flake*`, `flake-parts/**`,
  `hosts/dathomir/**`, `infra/**`, `modules/nixos/**`, or `secrets/oci.yaml`.
- **Jobs:** builds the image on a native `ubuntu-24.04-arm` runner, `plan`s,
  then `apply`s into the `oci-production` GitHub environment (set up any
  required reviewers there).
- **CI secrets:** `SOPS_AGE_KEY` decrypts `secrets/oci.yaml` in CI.

Manual runs:

```bash
gh workflow run deploy-oci.yml -f apply=false   # plan only
gh workflow run deploy-oci.yml -f apply=true    # plan + apply
```

See [docs/deployment.md](deployment.md) for command details.

## Always-Free constraints

`infra/variables.tf` enforces the Always Free envelope:

- Shape is locked to `VM.Standard.A1.Flex` (`ARM`).
- `instance_ocpus` ≤ **2** and `instance_memory_gbs` ≤ **12** (free-tier A1 caps).
- `assign_public_ip` defaults to `false` — access is **Tailscale-only**; don't
  expose a public IP/SSH.
- Multiple availability/fault domains are tried automatically.

### "Out of host capacity" (A1 is frequently oversubscribed)

If apply fails with insufficient capacity:

1. Bump `availability_domain_number` (only helps in multi-AD regions).
2. Set `fault_domain` to `FAULT-DOMAIN-1` / `-2` / `-3`.
3. Re-run `just -f infra/justfile tf apply`. May require retrying at different
   times — free ARM capacity is scarce and shared.

## Accessing the VPS

`dathomir` has no public IP and disallows root password login
(`PermitRootLogin = "no"`). Connect over Tailscale:

```bash
ssh ubuntu@dathomir   # or the tailnet hostname, e.g. dathomir.<tailnet>.ts.net
```

`cloud-init` seeds the authorized ssh key from `infra/variables.tf`
(`ssh_public_key`, defaulting to the primary dathomir access key) and writes the
Tailscale auth key from `secrets/oci.yaml`, so `tailscale-autoconnect` joins the
tailnet at first boot automatically.

## Destroying the VPS

Destroying the instance is reversible (state is in R2), but remember it also
prunes nothing else — the R2 bucket also holds Restic backups (see
[docs/backups.md](backups.md)). Don't delete the bucket without checking both.

```bash
just -f infra/justfile destroy
```

## Related docs

- [docs/deployment.md](deployment.md) — deploy/rollback/generations commands.
- [docs/backups.md](backups.md) — the shared R2 bucket and disaster recovery.
- [docs/secrets.md](secrets.md) — `secrets/oci.yaml` and OCI credentials.
