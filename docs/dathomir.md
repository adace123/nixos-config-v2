# dathomir — OCI Always-Free VPS

`dathomir` is an aarch64-linux VPS running on
[Oracle Cloud Infrastructure](https://www.oracle.com/cloud/) (OCI) inside the
**Always Free** tier. It is provisioned with OpenTofu from the `infra/`
directory, boots an Oracle **platform image**, is converted to NixOS in place,
and joins your Tailscale tailnet. There is **no public IP** — all access goes
through Tailscale.

## Architecture

| Piece | Where |
|-------|-------|
| Host identity (hostname, ssh keys) | `hosts/dathomir/default.nix` |
| NixOS system | `flake-parts/nixos.nix` (inline module) |
| Conversion (platform image → NixOS) | `scripts/dathomir-convert.sh` + `infra/dathomir-infect-import.nix` |
| OpenTofu infrastructure (`infra/` dir) | `infra/main.tf`, `providers.tf`, etc. |
| OCI / R2 secrets | `secrets/oci.yaml` |
| Remote state | Cloudflare R2 (`infra/backend.tf`) |

The NixOS configuration is small by design. It intentionally does **not** import
the home-server modules (`base.nix`, `common.nix`, `home-assistant`, …) —
`dathomir` is a general-purpose compute node, not a second home server. It also
no longer imports `virtualisation/oci-image.nix`, because there is no custom
image to boot. Its `fileSystems` describe the platform image's own partitions,
which `nixos-infect` keeps rather than repartitioning:

| Partition | Filesystem | Label | Mount |
|---|---|---|---|
| `sda1` | ext4 | `cloudimg-rootfs` | `/` |
| `sda16` | ext4 | `BOOT` | `/boot` |
| `sda15` | vfat | `UEFI` | `/boot/efi` |

The ESP is addressed by filesystem label because this image has no
`/dev/disk/by-partlabel` at all — an easy thing to get wrong and an unbootable
box to get wrong it.

## Why there is no custom image (Always Free forbids them)

The original design built a NixOS `qcow2`
(`.#packages.aarch64-linux.vps-image`), uploaded it to OCI Object Storage and
imported it as a **custom image** (`oci_core_image`, `source_type =
"objectStorageTuple"`). On an Always Free tenancy that can never work:

```text
Error: 400-QuotaExceeded, You have reached the maximum quota allowed for
custom-image-count in ocid1.tenancy.oc1..aaaaaaaa…
  Service: Core Image / Operation Name: CreateImage
```

Every `apply` from 2026-08-15 onward failed this way. The tenancy's compute limit
is the cause, not leftover images or a policy of ours:

```bash
# limit value: 0 (Always Free). The account itself is fine — A1 compute is intact.
oci limits value list --compartment-id <tenancy> \
  --service-name compute --all \
  --query 'data[?name==`custom-image-count` || name==`standard-a1-core-count`].[name,value]'
```

`oci limits quota list` is empty and there are no child compartments, so there is
nothing to loosen — and a quota policy cannot raise an Oracle-imposed service
limit anyway. Upgrading the tenancy to Pay As You Go would lift it; `dathomir`
deliberately stays free instead, and boots a **platform image**: platform images
are not counted against `custom-image-count`.

## How provisioning works

```text
just -f infra/justfile init              # once: remote state in R2
just -f infra/justfile apply-retry       # create the instance (Ubuntu platform image)
        │
        ▼  cloud-init: installs Tailscale, joins the tailnet as `dathomir`
   ubuntu@dathomir  ──────────────────────  reachable over the tailnet
        │
        ▼  just dathomir-convert         # operator-run, one command
   nixos-infect replaces the OS, keeping the platform image's
   partitioning, bootloader and Tailscale node identity
        │
        ▼  same command converges onto the flake config
   NixOS running `.#nixosConfigurations.dathomir`, root SSH over Tailscale
```

`nixos-infect` is pinned by revision *and* SHA-256 in
`scripts/dathomir-convert.sh`: it is fetched on the workstation, verified against
that hash, and only then copied to the host — nothing unverified is ever piped
into a root shell. It rewrites the root filesystem in place, which is why the
conversion is a
deliberate operator step rather than something cloud-init does unattended: if it
fails, the box stays Ubuntu and reachable, and re-running is one command. After
a successful conversion the instance is NixOS, and later changes are ordinary
deploys:

```bash
NHOST=dathomir just nixos-deploy dathomir
```

Before the pivot the script copies the Tailscale auth key out of
`/var/lib/tailscale/` into `/etc/nixos/` (`NIXOS_LUSTRATE` carries `/etc/nixos`
across and discards `/var`), and adds `var/lib/tailscale` to the preserve list so
the node keeps its identity — a single-use auth key would otherwise leave the
converted box unreachable. The NixOS side reads the key from
`/etc/nixos/tailscale-authkey`. Migrating that to sops-nix needs the host's age
key installed from 1Password first, so it is not wired up yet — and note
`secrets/dathomir.yaml` is currently empty, so that migration would add
`ts-auth-key` back rather than find it already there.

## infra/ (OpenTofu)

The `infra/` directory is a self-contained OpenTofu workspace:

| File | Purpose |
|------|---------|
| `providers.tf` | OCI provider config |
| `main.tf` | VCN, subnet, security list, instance, cloud-init (Tailscale auth key) |
| `variables.tf` | Always-Free-constrained inputs (shape, OCPUs, memory, AD/fault domain, platform image) |
| `backend.tf` | Remote state in R2 |
| `tofu-env.sh` | Decrypts `secrets/oci.yaml` and exports OCI + R2 vars for OpenTofu |
| `dathomir-infect-import.nix` | Module `nixos-infect` injects during the conversion |
| `terraform.tfvars.example` | Non-secret local config template |
| `justfile` | `just -f infra/justfile <recipe>` — OpenTofu workflow |

### Remote state (Cloudflare R2)

Terraform/OpenTofu state is stored remotely in the same R2 bucket as the Restic
backups (subkey `infra/terraform.tfstate`). Initialize once with:

```bash
just -f infra/justfile init
```

`init` passes the backend config via credentials from `secrets/oci.yaml`. The
R2 bucket must exist before the first `init` — see the note in `infra/backend.tf`.

## Local (manual) workflow

You normally don't run this by hand — but the A1 capacity hunt usually means
running the retry loop until a free host appears:

```bash
# 1. One-time backend (R2 state) setup
just -f infra/justfile init

# 2. Plan
just -f infra/justfile tf plan

# 3. Apply, retrying across fault domains until capacity appears
just -f infra/justfile apply-retry

# 4. Convert the Ubuntu instance to NixOS (operator-run, over the tailnet)
just dathomir-convert

# 5. Inspect / destroy
just -f infra/justfile tf plan -destroy
just -f infra/justfile destroy
```

Each command runs inside the `infra` dev shell (`nix develop .#infra`) and
decrypts `secrets/oci.yaml` on the fly — the OCI private key is written to a
temp file and cleaned up on exit.

## GitHub Actions deploy

The `deploy-oci.yml` workflow still drives OpenTofu, but it no longer builds an
image (there is nothing to build: the instance boots a platform image and the
conversion is operator-run over the tailnet, which CI has no path into).

- **Trigger:** manual dispatch.
- **Jobs:** `plan`, then `apply` into the `oci-production` GitHub environment
  (set up any required reviewers there).
- **CI secrets:** `SOPS_AGE_KEY` decrypts `secrets/oci.yaml` in CI.

```bash
gh workflow run deploy-oci.yml -f apply=false   # plan only
gh workflow run deploy-oci.yml -f apply=true    # plan + apply
```

See [docs/deployment.md](deployment.md) for command details.

## Always-Free constraints

`infra/variables.tf` enforces the free envelope:

- Shape is locked to `VM.Standard.A1.Flex` (`ARM`).
- `instance_ocpus` ≤ **2** and `instance_memory_gbs` ≤ **12** (free-tier A1 caps).
- `assign_public_ip` defaults to `false` — access is **Tailscale-only**; don't
  expose a public IP/SSH.
- `custom-image-count` is **0**: Oracle-imposed, and now additionally pinned by
  the `always-free-envelope` quota policy below. No custom image can be created
  or imported, so never reintroduce `oci_core_image` here — boot a platform image
  instead.
- Only one availability domain exists (`FYEl:US-SANJOSE-1-AD-1` in
  `us-sanjose-1`), so `availability_domain_number` has nothing to bump to.

### Staying inside Always Free (and what would bill)

Upgrading does not end the free tier. Oracle's docs: *"Oracle doesn't charge for
Always Free resources after you upgrade, and will only charge you for resource
usage above the Always Free limits."* A 2 OCPU / 12 GB A1 instance is exactly the
Always Free compute allowance — Oracle meters it as **1,500 OCPU hours and 9,000
GB hours per month** for *all* tenancies (free or paid), which is 2 OCPU + 12 GB
running continuously.

There is no hard spend cap — OCI budgets send email alerts, they do not stop
spend — which is why the tenancy additionally carries a quota policy that caps
resource *quantities* (see [Guardrails in place](#guardrails-in-place)). Quotas
cannot cap a service they have no quota for, so that is near-total protection,
not a guarantee. What can actually bill, and the guard already in the repo:

| Billable if exceeded | Guard |
|---|---|
| A1 compute above 2 OCPU / 12 GB (metered hourly, so over-provisioning bills even if idle) | `lifecycle.precondition` in `main.tf` + the `variables.tf` validations refuse non-free shapes and sizes |
| Block volume above 200 GB total (the instance's boot volume is 50 GB) | none needed; one 50 GB boot volume |
| Object Storage above 10 GB Standard on a paid account | the image bucket is deleted and no custom image is created any more |
| Outbound data transfer above 10 TB/month | none; not reachable for this box |
| An unattached reserved public IP | `assign_public_ip = false` |

Oracle also documents reclaiming **idle** Always Free instances: a compute
instance is deemed idle if, over 7 days, 95th-percentile CPU, network and memory
utilisation are all under 20%. The Free Tier FAQ adds that accounts left idle for
30 days may be treated as abandoned. That matters for a general-purpose node
like dathomir, which is quiet by design — and it is reportedly not a concern on a
paid account.

### Guardrails in place

Two guardrails live in OCI rather than in this repo (there is no OpenTofu
resource for them; they were created with the OCI CLI):

- **Budget `Always-Free-Alert`** — 1 USD/month against the tenancy, with one
  alert rule that emails the account owner when *actual* spend reaches $1.
  Budgets only notify; they never block.
- **Quota policy `always-free-envelope`** — a hard cap at the free envelope, so
  over-provisioning *fails* instead of billing:

  ```text
  set compute-core quota standard-a1-core-count to 2 in tenancy
  set compute-memory quota standard-a1-memory-count to 12 in tenancy
  set block-storage quota total-storage-gb to 200 in tenancy
  set object-storage quota storage-bytes to 10737418240 in tenancy
  set compute quota custom-image-count to 0 in tenancy
  ```

  Two details to know before touching it. `standard-a1-core-count` is
  **AD-scoped**, so its value is *per availability domain* — 2 OCPU is exactly
  what dathomir requests, and a cap of 1 would block it. And the service families
  are not the limits-API service names: cores are in `compute-core`, memory in
  `compute-memory`, custom images in plain `compute`. Inspect, change or remove
  it with:

  ```bash
  oci limits quota list --compartment-id <tenancy> --output json
  oci limits quota update --quota-id <quota-ocid> --force --statements '[...]'
  oci limits quota delete --quota-id <quota-ocid>
  ```

  If a future change legitimately needs more than the free allowance, raise or
  delete this policy first — otherwise the API refuses with a quota error that
  looks unrelated to the change being made.

### "Out of host capacity" (A1 is frequently oversubscribed)

Free ARM capacity is scarce and shared, so `apply` usually fails first with:

```text
Error: 500-InternalError, Out of host capacity.
```

What actually helps, in order of effect:

1. **Persist.** Capacity is released in small, random windows and goes to
   whoever happens to be asking at that moment — the community scripts that
   solve this poll every 5-20 minutes for days at a time. `apply-retry` cycles
   the fault domains and stops on any non-capacity error; run it repeatedly:

   ```bash
   just -f infra/justfile apply-retry
   MAX_ATTEMPTS=240 SLEEP_SECONDS=120 just -f infra/justfile apply-retry   # ~8h
   ```

2. **Ask before you launch.** OCI's capacity report says whether capacity exists
   for a shape *without* creating anything — one cheap read-only call instead of
   a plan+apply, so it can tighten the retry cadence:

   ```bash
   oci compute compute-capacity-report create \
     --compartment-id "$TENANCY_OCID" \
     --availability-domain FYEl:US-SANJOSE-1-AD-1 \
     --shape-availabilities '[{"instanceShape":"VM.Standard.A1.Flex",
       "instanceShapeConfig":{"ocpus":2,"memoryInGBs":12},
       "faultDomain":"FAULT-DOMAIN-1"}]'
   ```

   Treat it as a signal, not a hard gate: in this region it has only ever
   answered `OUT_OF_HOST_CAPACITY`, and no non-ARM shape reported `AVAILABLE`
   either, so a green report is not guaranteed to arrive before the capacity
   does. Keep making real attempts.

3. **Upgrade the tenancy to Pay As You Go.** Multiple independent sources —
   including the maintainer of the best-known retry script — report that PAYG
   accounts are not subject to this lottery and keep the Always Free allowance;
   the mid-2026 cut to 2 OCPU / 12 GB was reported as applying to Always Free
   tenancies only (Oracle has not confirmed that publicly).
   It costs a payment method on the account, and dathomir stays free only while
   it stays inside the allowances, which is why this was deliberately not done.
   The same sources warn that Oracle reclaims *idle* Always Free resources, so an
   unused dathomir can be taken back even after you win the lottery.

Checked, and they do **not** help here:

- **Bumping the availability domain** — this region has exactly one
  (`FYEl:US-SANJOSE-1-AD-1`), so `availability_domain_number` has nothing to
  point at.
- **Asking for less** — the capacity report answers `OUT_OF_HOST_CAPACITY` for
  1 OCPU / 1 GB as well as 1/6 and 2/12, so a smaller request does not unlock
  this region.
- **Another region** — Always Free ARM is only usable in the tenancy's home
  region.
- The often-repeated *"launch a bigger shape, then shrink to the free limits"*
  trick is PAYG-only, and 2/12 is the ceiling for this tenancy anyway
  (`standard-a1-core-count = 2`, `standard-a1-memory-count = 12`).

## Accessing the VPS

`dathomir` has no public IP. Connect over Tailscale:

```bash
ssh root@dathomir      # NixOS
ssh ubuntu@dathomir    # only before the conversion
```

The Tailscale auth key in `secrets/oci.yaml` decides *which* tailnet the instance
joins: cloud-init uses whatever key it is handed, and an auth key belongs to one
account, so a key from a different tailnet silently registers the box there
instead — along with its DNS name. Keep that key and the tailnet you expect this
host to appear on in step, and note that a Tailscale account switch on your
workstation does not move the host.

Key handling differs either side of the conversion. The converted system takes
its root keys from `hosts/dathomir/default.nix` (three of them). The **pre-conversion**
Ubuntu stage authorizes only `ssh_public_key` from `infra/variables.tf`, and OCI
will not add keys to a running instance — `ssh_authorized_keys` cannot be changed
after launch — so widening that variable only takes effect on the next instance
replacement, which means re-running the conversion.

`infra/variables.tf` seeds the `ssh_authorized_keys` metadata (default: the
primary dathomir access key), which cloud-init applies to the `ubuntu` user;
`nixos-infect` then gives root the same keys. In NixOS, root login is
key-only (`PermitRootLogin = "prohibit-password"`), which is what
`just nixos-deploy` needs — a change from the previous design, which forbade
root login entirely because nothing deployed to the box.

If the tailnet name comes back as `dathomir-1`, note that deleting the stale node
does not rename the live one: the suffix was fixed when this node registered while
`dathomir` was taken. Rename the device in the Tailscale admin console (Devices →
this host) and MagicDNS follows — the host's own hostname is already `dathomir`, so
nothing on the box needs changing.

## Beszel hub (tailnet-only, with a real TLS name)

dathomir runs the beszel **hub**, as the Pi hosts do, published by Caddy at
`beszel-domain` from `secrets/dathomir.yaml` with a Cloudflare DNS-01
certificate. The name is a genuine one on the Cloudflare zone, but its A record
points at this host's **tailnet** address — so it resolves, and is unroutable
outside the tailnet. No public IP, no inbound firewall rule, no tunnel.

Caddy's build (upstream plus the Cloudflare DNS plugin) comes from
`nix-caddy.nix`, shared with the Pi hosts so the plugin version and its hash are
defined once.

Two steps are manual, and **the order matters**:

1. Install the host's age key at `/var/lib/sops-nix/key.txt` — it is in 1Password,
   and also on the workstation at `~/.config/sops/age/host-keys/dathomir.txt`.
   Do this *before* deploying: Caddy's config file comes from a sops template, so
   a switch without the key leaves Caddy broken.
2. Point the `beszel-domain` A record at dathomir's tailnet address
   (`tailscale ip -4 dathomir-1`). Tailscale keeps a node's address stable.

The hub itself stays on `127.0.0.1:8090`, so only Caddy is reachable. Clients must
be on the same tailnet as dathomir — including any host that should *report* to
the hub, since Tailscale-only cuts both ways.

The hub reads `APP_URL` from a sops-rendered env file (`beszel-hub-env`) so the
links it puts in notifications point at `https://<beszel-domain>` rather than the
built-in `http://localhost:8090` fallback, which is useless from a phone. If you
change the hub's public name, the alert links follow the secret automatically.

dathomir also runs the **agent**, and coruscant runs one pointed at this hub over
the tailnet. Both authenticate with a **universal token** — create it once at
`/settings/tokens` and put the same value in each host's `beszel-token` secret —
and dial the hub over an outgoing WebSocket connection. So nothing has to reach the
agent, the hub needs no per-system key, and provisioning an agent is a shared
secret, the hub's SSH public key, plus a deploy rather than a click in the UI.
The agent also needs the hub's SSH public key (`beszel-key`, derived from the
hub's keypair with `ssh-keygen -y`) to verify the hub's auth-challenge signature —
beszel agents refuse to start without it even in token mode. The unit also
joins `systemd-journal` so the hub UI can show each service's journal, not just
its status — without that group the logs panel is hidden. A missing secret fails
activation, so add it before deploying.

## Pocket ID (passkey login for the hub)

`id.<domain>` serves [Pocket ID](https://pocket-id.org) from dathomir — a
passkey-based identity provider the hub delegates its logins to, so signing in uses
a passkey rather than a password. It is published exactly like the hub: a public
name whose A record points at this host's tailnet address.

Two things are worth knowing before touching its configuration:

- **`APP_URL` and `ENCRYPTION_KEY` are supplied through
  `services.pocket-id.credentials`, not `settings`.** A settings value is rendered
  into the Nix store at build time, where a sops placeholder cannot be substituted
  (it lands literally, and Pocket ID rejects it) — and the module appends its own
  settings file *after* the host's, so its `APP_URL = http://localhost` default would
  win regardless. Credentials are exported inside the start script, after
  `EnvironmentFile` is applied. Pocket ID also wants a *full URL*: a credential is
  read verbatim, so the `https://` scheme has to be in the file a template renders —
  pointing the credential at the bare domain secret gives "APP_URL must not contain a
  path", because a scheme-less string parses as one.
- **The OIDC client for the hub lives in the hub's own settings, not this repo**
  (client id, secret and the three endpoints). It is the one piece of this setup that
  is not declarative.

Enrolment: open `https://id.<domain>`, create the admin account with a passkey, then
**Administration → OIDC Clients → Add** with callback
`https://monitoring.<domain>/api/oauth2-redirect`, PKCE on, and verified emails on
(the hub requires a verified address). Paste those values into the hub's OAuth2
settings.

The hub runs with `USER_CREATION=true`. **`DISABLE_PASSWORD_AUTH=true` is deliberately
not set** — switch it on only once a passkey login has been verified, because doing
it first locks everyone out of the hub.

Neither Pocket ID's database nor the hub's is backed up, so losing this host means
re-enrolling passkeys and re-adding systems; see [docs/backups.md](backups.md).

## Destroying the VPS

Destroying the instance is reversible (state is in R2), but remember it also
prunes nothing else — the R2 bucket also holds Restic backups (see
[docs/backups.md](backups.md)). Don't delete the bucket without checking both.

```bash
just -f infra/justfile destroy
```

**This is deliberately blocked by a `prevent_destroy` lifecycle guard** in
`infra/main.tf`: the instance's OS is not reproducible from the platform image —
it was converted in place — so destroying it throws the conversion away. Delete
the `lifecycle` block first when a replacement is genuinely what you want, then
re-run `just dathomir-convert` afterwards.

Note that plans currently *fail* with `Resource instance cannot be destroyed`,
because the instance metadata still carries the throwaway key used during the
first provisioning (OCI refuses to change `ssh_authorized_keys` on a live
instance, so the metadata cannot be reconciled in place). Accepting one
replacement resolves it for good — and is the moment to widen `ssh_public_key`
first if you want more than one key usable during the pre-conversion window.

## Related docs

- [docs/deployment.md](deployment.md) — deploy/rollback/generations commands.
- [docs/backups.md](backups.md) — the shared R2 bucket and disaster recovery.
- [docs/secrets.md](secrets.md) — `secrets/oci.yaml` and OCI credentials.
