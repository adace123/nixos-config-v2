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
| `main.tf` | Instance, SSH key, cloud-init (Tailscale auth), networking |
| `outputs.tf` | Useful output values (e.g. instance OCID) |
| `backend.tf` | Remote state in R2 (S3-compatible backend) |
| `tofu-env.sh` | `sops -d` secrets and export OCI/R2 env vars for OpenTofu |
| `justfile` | `just -f infra/justfile <recipe>` workflow |
| `terraform.tfvars.example` | Template for non-secret local vars |
| `result/` | `.gitignore`d output symlink to the built image |

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
| `build-image` | Build `.#packages.aarch64-linux.vps-image` → `./result/nixos.qcow2` |
| `init` | One-time backend (R2 state) init |
| `tf <cmd>` | Run any tofu command with secrets injected (e.g. `just -f infra/justfile tf plan`) |
| `tofu <cmd>` | Alias for `tf` |
| `plan-apply` | Plan + apply in one process (keeps the temp private-key path stable) |
| `destroy` | Plan + destroy the managed resources |

> `build-image` requires an aarch64-linux builder. On a Darwin-only machine
> without one it will fail — use the GitHub Actions workflow instead
> (`just nixos-build-ci` is for SD images; see `deploy-oci.yml` for the OCI image).

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
just -f infra/justfile build-image   # produce ./result/nixos.qcow2
just -f infra/justfile init          # backend setup (once)
just -f infra/justfile tf plan       # preview
just -f infra/justfile tf apply      # deploy
```

The CI-equivalent `deploy-oci.yml` runs the same commands on a native arm64
runner with `SOPS_AGE_KEY`. See [docs/dathomir.md](../docs/dathomir.md) and
[docs/deployment.md](../docs/deployment.md).
