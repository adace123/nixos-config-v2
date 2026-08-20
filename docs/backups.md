# Backups (Restic → Cloudflare R2)

Home Assistant on `coruscant` is backed up automatically with
[Restic](https://restic.net/) to a private S3-compatible
[Cloudflare R2](https://www.cloudflare.com/products/r2/) bucket. The backup is
declarative — managed entirely by `modules/nixos/home-assistant/restic.nix` on
the NixOS host — and requires no manual action in steady state.

## What is backed up

| Item | Path | Notes |
|------|------|-------|
| Home Assistant data | `/var/lib/hass` | The persistent HA config, DB, and automations dir |

The backup **excludes** `deps`, `logs`, and `tts` (regenerable/cache data)
under `/var/lib/hass`.

During a backup, the Home Assistant Podman container is **stopped** so the
snapshot is consistent, then started again (restart is guaranteed via a trap
even if the backup fails).

## Where it goes

Restic writes to:

```text
s3:<cloudflare-endpoint>/<cloudflare-bucket>/coruscant
```

- Repository subpath: `coruscant` (keeps room for future hosts in the same bucket).
- R2 credentials, bucket name, endpoint, and the `restic-password` live in
  `secrets/cloudflare.yaml` (see [docs/secrets.md](secrets.md)).
- Every snapshot is tagged `home-assistant`.

## Schedule

Defined in `modules/nixos/home-assistant/restic.nix`:

| Job | When | Command |
|-----|------|---------|
| Backup + prune | Daily 03:30 (`Persistent`, +15 min randomized delay) | `restic backup` then `restic forget --prune` |
| Repository check | Weekly Sunday 04:30 (+30 min randomized delay) | `restic check` |

## Retention

`restic forget --prune` keeps:

- **14** daily snapshots
- **8** weekly snapshots
- **6** monthly snapshots

Older snapshots are pruned. `--prune` frees the underlying R2 storage.

## Listing backups

From macOS (or anywhere with the R2 credentials), list the objects in the
bucket:

```bash
just r2-list                # all objects
just r2-list coruscant      # only the restic repository (prefix filter)
```

This decrypts `secrets/cloudflare.yaml` on the fly and prints `Key`,
`Size (MB)`, and `Last Modified` columns.

To see restic snapshots themselves (requires the restic password and endpoint):

```bash
# from a shell with the same env as the host (see restic.nix template)
AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_DEFAULT_REGION=auto \
RESTIC_REPOSITORY=s3:<endpoint>/<bucket>/coruscant \
RESTIC_PASSWORD_FILE=<path-to-restic-password> \
restic -o s3.bucket-lookup=path snapshots
```

## Restoring Home Assistant

To restore the most recent snapshot on the NixOS host:

```bash
# 1. Stop HA so it doesn't write while restoring
systemctl stop podman-home-assistant.service

# 2. Restore, using the same env the backup service uses (set from the sops
#    template, or run a one-off with the R2 + restic-password values)
restic -o s3.bucket-lookup=path restore latest --target /

# 3. Start HA again
systemctl start podman-home-assistant.service
```

Because the repository path inside the bucket is `/coruscant` and the data
lives at `/var/lib/hass`, `restore latest --target /` writes the files back to
`/var/lib/hass/...`. To restore a specific snapshot, replace `latest` with the
snapshot ID from `restic snapshots`.

> **Order matters:** stop HA first. Restoring while the container is running
> risks clobbering a newer state with an older snapshot.

## Secret key & disaster recovery

The `restic-password` and all R2 / OCI credentials are SOPS-encrypted. Backing
up your age key is part of making the backups restorable in a crisis — see
[Recovering Access](docs/secrets.md#recovering-access) in
[docs/secrets.md](secrets.md), and back it up to 1Password with:

```bash
just backup-key
```

The R2 bucket also stores the OpenTofu remote state (`infra/terraform.tfstate`)
— see [docs/dathomir.md](dathomir.md). Destroying the bucket would lose both the
backup history and the VPS state; treat it as a production resource.
