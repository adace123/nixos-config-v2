# Backups (Restic → Cloudflare R2)

Home Assistant on `coruscant` and the beszel hub's state on `dathomir` are backed
up automatically with [Restic](https://restic.net/) to a private S3-compatible
[Cloudflare R2](https://www.cloudflare.com/products/r2/) bucket. The backup is
declarative — `modules/nixos/home-assistant/restic.nix` on the Pi hosts and
`modules/nixos/beszel-hub-restic.nix` on dathomir — and requires no manual action
in steady state.

Each host writes to its **own repository** inside the bucket (`coruscant`,
`dathomir`), so one never prunes the other's snapshots.

## What is backed up

| Item | Host | Path | Repository |
|------|------|------|------------|
| Home Assistant data | coruscant | `/var/lib/hass` | `coruscant` |
| Beszel hub state | dathomir | `/var/lib/private/beszel-hub` | `dathomir` |

The backup **excludes** `deps`, `logs`, and `tts` (regenerable/cache data)
under `/var/lib/hass`.

The snapshot size is dominated by the recorder database
(`home-assistant_v2.db`): 960M of the 1.1G directory in October 2026. Its
retention is 30 days — see
[docs/home-assistant.md → Recorder and history retention](home-assistant.md#recorder-and-history-retention)
— so shortening that horizon is the cheapest way to shrink both the snapshot and
each nightly upload.

During a backup, the Home Assistant Podman container is **stopped** so the
snapshot is consistent, then started again (restart is guaranteed via a trap
even if the backup fails).

## Where it goes

Restic writes to:

```text
s3:<cloudflare-endpoint>/<cloudflare-bucket>/coruscant   # Home Assistant
s3:<cloudflare-endpoint>/<cloudflare-bucket>/dathomir    # beszel hub
```

- Repository subpath: `coruscant` and `dathomir` (keeps room for future hosts in
  the same bucket).
- R2 credentials, bucket name, endpoint, and the `restic-password` live in
  `secrets/cloudflare.yaml` (see [docs/secrets.md](secrets.md)). Every host that
  backs up is listed as an age recipient of that file.
- Snapshots are tagged `home-assistant` or `beszel-hub`.

## Schedule

Defined in `modules/nixos/home-assistant/restic.nix` (Home Assistant) and
`modules/nixos/beszel-hub-restic.nix` (beszel hub):

| Job | When | Command |
|-----|------|---------|
| HA backup + prune | Daily 03:30 (`Persistent`, +15 min randomized delay) | `restic backup` then `restic forget --prune` |
| HA repository check | Weekly Sunday 04:30 (+30 min randomized delay) | `restic check` |
| Hub backup + prune | Daily 03:45 (`Persistent`, +15 min randomized delay) | `restic backup` then `restic forget --prune` |
| Hub repository check | Weekly Sunday 05:00 (+30 min randomized delay) | `restic check` |

Both hosts pass `--retry-lock` and wait for the repository lock instead of failing.
This matters because the Pi hosts boot without an RTC: when the clock is stepped
forward, every missed `OnCalendar` timer elapses at once, and `RandomizedDelaySec`
does not separate those catch-up runs — so the backup and the check could grab the
lock within seconds of each other and the loser aborted with `repository is already
locked` (coruscant, 2026-10-23).

Note the backup deliberately stops `podman-home-assistant.service` first (and
restarts it via a shell `trap`) so the snapshot is consistent; that is the reason
Home Assistant briefly stops around 03:30. The beszel hub job does the same to
`beszel-hub.service` for the same reason — PocketBase keeps SQLite in WAL mode, and
only a clean shutdown checkpoints it into a consistent `data.db` — so the hub is
also briefly unreachable just after 03:45, and no monitoring alerts are delivered in
that window.

## The beszel hub's state (dathomir)

`modules/nixos/beszel-hub-restic.nix` covers the one thing on the VPS that git
does not: `/var/lib/private/beszel-hub` holds the hub's PocketBase database — user
accounts, notification channels (email + the ntfy topic), every **alert rule and
threshold**, alert history, and the hub's ed25519 keypair that all agents use to
verify it. Alert rules are UI objects, so losing this directory means rebuilding
the monitoring setup by hand after any instance rebuild.

**Trade-off, stated plainly:** the R2 credentials are scoped to the bucket, not to a
repository path. dathomir therefore also holds credentials that can delete the Home
Assistant snapshots. That is the cost of backing up from the machine that would need
restoring; the improvement is a separate bucket and a dedicated R2 token for this
repository, which is a Cloudflare-side change (see the note in `.sops.yaml`).

Restore on a fresh instance, after `just dathomir-convert` has it running NixOS:

```bash
systemctl stop beszel-hub.service
RESTIC_REPOSITORY=s3:<endpoint>/<bucket>/dathomir restic -o s3.bucket-lookup=path \
  restore latest --target /
systemctl start beszel-hub.service
```

Agents reconnect on their own once the hub is back: they dial out with the same
universal token, and the restored `id_ed25519` is what they already trust.

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
