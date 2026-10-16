# infra — OCI OpenTofu workspace

This directory manages the Oracle Cloud Infrastructure (OCI) resources behind
the `dathomir` VPS (Always-Free ARM instance). It is a self-contained
[OpenTofu](https://opentofu.org/) workspace with remote state in Cloudflare R2.

For the higher-level picture (build → plan → apply → access → destroy) see
**[docs/dathomir.md](../docs/dathomir.md)**.

## Layout

| File | Purpose |
|------|---------|
| `providers.tf` | OCI provider + required versions |
| `variables.tf` | Always-Free-constrained inputs; OCI + R2 auth vars driven by `tofu-env.sh` |
| `main.tf` | VCN, subnet, security list, platform-image instance, cloud-init (Tailscale) |
| `dathomir-infect-import.nix` | NixOS module `nixos-infect` injects during the Ubuntu → NixOS conversion |
| `outputs.tf` | Useful output values (instance OCID, platform image OCID) |
| `backend.tf` | Remote state in R2 (S3-compatible backend) |
| `tofu-env.sh` | `sops -d` secrets and export OCI/R2 env vars for OpenTofu |
| `justfile` | `just -f infra/justfile <recipe>` workflow |
| `terraform.tfvars.example` | Template for non-secret local vars |

There is no built image to upload any more: an Always Free tenancy has
`custom-image-count = 0`, so `CreateImage` always fails and the instance boots an
Oracle platform image instead, converted to NixOS in place by
`scripts/dathomir-convert.sh`. See [docs/dathomir.md](../docs/dathomir.md).

## Prerequisites

- Nix (commands run inside `nix develop .#infra`, which provides `opentofu`,
  `sops`, `age`, `yq`, `just`).
- The age key able to decrypt `../secrets/oci.yaml`.
- An existing R2 bucket for remote state (create once — see `backend.tf`).

## Command reference

All commands are run from the repo root with `just -f infra/justfile <recipe>`
(or just `<recipe>` inside the `infra/` directory / dev shell).

| Recipe | Action |
|--------|--------|
| `edit-secrets` | Open `../secrets/oci.yaml` in sops |
| `init` | One-time backend (R2 state) init |
| `tf <cmd>` | Run any tofu command with secrets injected (e.g. `just -f infra/justfile tf plan`) |
| `tofu <cmd>` | Alias for `tf` |
| `plan-apply` | Plan + apply in one process (keeps the temp private-key path stable) |
| `apply-retry` | Apply, cycling A1 fault domains until free-tier capacity appears |
| `destroy` | Plan + destroy the managed resources |

> The A1 free tier is heavily oversubscribed, so a bare `apply` usually fails
> with `500-InternalError, Out of host capacity`. `apply-retry` exists for that:
> it cycles `FAULT-DOMAIN-1`/`-2`/`-3` (with `MAX_ATTEMPTS` / `SLEEP_SECONDS`
> overrides), stops on any non-capacity error, and is safe to repeat. Capacity
> is released in waves, so running it again later in the day often succeeds.

## Secrets

`tofu-env.sh` decrypts `../secrets/oci.yaml` and exports:

- OCI auth: `tenancy-id`, `user-ocid`, `fingerprint`, `region`,
  `compartment-ocid`, `private-key`, `public-key`
- R2 backend: `r2-access-key-id`, `r2-secret-access-key`, `r2-account-id`,
  `r2-bucket-name`
- `ts-auth-key` (Tailscale) → `TF_VAR_tailscale_auth_key`

These map to `TF_VAR_*` variables consumed by `variables.tf`. Nothing secret is
committed; only `terraform.tfvars.example` (non-secret) is tracked.

## Local develop loop

```bash
just -f infra/justfile init          # backend setup (once)
just -f infra/justfile tf plan       # preview
just -f infra/justfile apply-retry   # deploy, retrying across fault domains
just dathomir-convert                # platform image -> NixOS (operator-run)
```

The CI-equivalent `deploy-oci.yml` runs the same OpenTofu commands on a GitHub
runner with `SOPS_AGE_KEY`. It no longer builds or uploads an image: an Always
Free tenancy cannot import a custom image, so the instance boots a platform image
and `scripts/dathomir-convert.sh` replaces the OS in place. See
[docs/dathomir.md](../docs/dathomir.md) and
[docs/deployment.md](../docs/deployment.md).
