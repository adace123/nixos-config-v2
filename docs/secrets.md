# Secrets Management

This configuration uses [SOPS](https://getsops.io/) with
[age](https://age-encryption.org/) keys to encrypt secrets at rest.
SOPS-encrypted files are safe to commit to git — only holders of the age private
key can decrypt them.

The NixOS integration is provided by
[sops-nix](https://github.com/Mic92/sops-nix);
the macOS integration uses the sops-nix darwin module.

## Key Model: One Key Per Host

Each machine has its **own age identity**. A host can only decrypt the secrets
in its own `secrets/<hostname>.yaml` file — compromising one machine never
exposes another machine's secrets. A separate **admin (editing) key** lives on
your workstation and is used only for editing/re-encrypting secret files; it is
never deployed to any host.

```text
.sops.yaml                          ← which age public keys decrypt which files
secrets/endor.yaml                  ← endor's secrets (AI provider API keys)
secrets/coruscant.yaml              ← coruscant's secrets (Tailscale, Caddy, HA)
secrets/threepio.yaml               ← threepio's secrets (same set as coruscant)
secrets/dathomir.yaml               ← dathomir's secrets (currently ts-auth-key)
secrets/cloudflare.yaml             ← Restic → R2 credentials (both Pi hosts + CI)
secrets/oci.yaml                    ← OCI/OpenTofu state credentials (CI only)

~/.config/sops/admin-keys.txt       ← admin editing key on the workstation (NEVER commit)
~/.config/sops/age/keys.txt         ← THIS host's private key (endor uses this path;
                                       NixOS hosts use /var/lib/sops-nix/key.txt)
```

Modules select their secrets file automatically by hostname:

```nix
# modules/nixos/base.nix and modules/home/secrets.nix both use:
sops.defaultSopsFile = ../../secrets/${host.hostName}.yaml;
```

Private keys are backed up in 1Password:

| 1Password item | Contents |
|----------------|----------|
| `sops-nix age default key` | Admin editing key |
| `sops-nix age key - <host>` | Each host's private key |

## How It Works

At activation time, sops-nix decrypts `secrets/<hostname>.yaml` using the host's
private key and writes each requested secret as a file under `/run/secrets/`
(mode 0400 by default, owned by the requesting service user). Cloudflare R2
backup credentials (`secrets/cloudflare.yaml`) are shared by both Pi hosts and
referenced explicitly via `sopsFile` in `home-assistant/restic.nix`.

## Prerequisites

```bash
# Install sops and age via nix shell (or add to your packages)
nix shell nixpkgs#sops nixpkgs#age
```

## Editing Secrets

```bash
just edit-secrets                       # edits secrets/endor.yaml by default
just edit-secrets FILE=secrets/coruscant.yaml
```

The recipe sets `SOPS_AGE_KEY_FILE=~/.config/sops/admin-keys.txt`, so editing
uses the admin key regardless of which host key is installed locally. SOPS
decrypts, opens `$EDITOR`, and re-encrypts on save using the `.sops.yaml`
creation rules.

## Creating a New Secret

1. Edit the target host's file (see above) and add the key:

   ```yaml
   my-new-secret: "the secret value"
   ```

2. Declare it in a module consumed by that host:

   ```nix
   sops.secrets.my-new-secret = { };

   # Then use config.sops.secrets.my-new-secret.path in services
   ```

3. Deploy to the host.

If a secret is needed on several hosts, add it to each host's YAML file. Files
encrypted to multiple hosts' keys (e.g. `cloudflare.yaml`) are the exception,
not the rule.

## Installing a Host Key on a NixOS Machine

Before first deploy (or after key rotation), install the host's private key:

```bash
just install-sops-key coruscant root@coruscant.local
```

The recipe prefers the 1Password document (`sops-nix age key - <host>`) and
falls back to `~/.config/sops/age/host-keys/<host>.txt`. It writes
`/var/lib/sops-nix/key.txt` on the target with mode 0600.

For a fresh provision (nixos-anywhere / SD image), copy the key into
`nixos-files/var/lib/sops-nix/key.txt` before flashing instead:

```bash
mkdir -p nixos-files/var/lib/sops-nix
cp ~/.config/sops/age/host-keys/coruscant.txt nixos-files/var/lib/sops-nix/key.txt
```

On the macOS workstation, the host key lives at the standard home-manager path:

```bash
cp ~/.config/sops/age/host-keys/endor.txt ~/.config/sops/age/keys.txt
```

## Adding a New Host

1. Generate a key pair for the new host (on any machine):

   ```bash
   nix shell nixpkgs#age -c age-keygen -o ~/.config/sops/age/host-keys/<host>.txt
   ```

2. Store the private key in 1Password:

   ```bash
   op document create ~/.config/sops/age/host-keys/<host>.txt \
     --title "sops-nix age key - <host>" --tags "sops-nix,age-key"
   ```

3. Add an anchor and a creation rule to `.sops.yaml` (copy the pattern of an
   existing `<host>.yaml` rule).

4. Create `secrets/<host>.yaml` with the secrets that host needs:

   ```bash
   # start from a copy of an existing file, then trim/add keys
   just edit-secrets FILE=secrets/<host>.yaml
   ```

5. Update `modules/nixos/base.nix`'s declared `sops.secrets` (or the consuming
   module) if the new host needs different keys than the defaults.

6. Install the key on the machine (see previous section) and deploy.

## Rotating a Host Key

Use this procedure when a host is compromised or during periodic rotation.

1. Generate a new key pair for the host (step 1 above).

2. Replace the host anchor's public key in `.sops.yaml`.

3. Re-encrypt every file whose creation rule includes that host:

   ```bash
   export SOPS_AGE_KEY_FILE=~/.config/sops/admin-keys.txt
   sops updatekeys secrets/<host>.yaml
   sops updatekeys secrets/cloudflare.yaml   # if the host was a recipient
   ```

4. Commit `.sops.yaml` and the updated secret files.

5. Install the new private key on the host (`just install-sops-key ...`) and
   redeploy so `/run/secrets` is regenerated.

6. Remove the old private key from the compromised machine (and delete the old
   1Password entry).

## Rotating the Admin Editing Key

1. Back up the current key first (`just backup-key`) so nothing is lost.
2. Generate the replacement: `just init-sops`.
3. Add the new public key to every creation rule in `.sops.yaml`.
4. Re-encrypt all files in `secrets/` with `sops updatekeys <file>`.
5. Update the `sops-nix age default key` document in 1Password.
6. Remove the old public key from `.sops.yaml`, re-encrypt again, commit.

## GitHub Actions Secrets for OCI Deploy

The OCI deploy workflow decrypts `secrets/oci.yaml` in CI using a single age
key. The plaintext secrets never appear as individual GitHub secrets.

Required GitHub secret:

| Secret | Source / value |
|--------|----------------|
| `SOPS_AGE_KEY` | The private age key whose public key is the `github_actions_oci` recipient in `.sops.yaml` |

All OCI and R2 credentials are read from `secrets/oci.yaml` at plan/apply time
by `infra/tofu-env.sh` (via `sops -d`). To rotate or change a credential, edit
the encrypted file locally rather than changing GitHub secrets.

The apply job also references the `oci-production` GitHub environment. Use that
environment for required reviewers or wait timers on auto-deploys from `main`.

## Recovering Access

All private keys are backed up in 1Password:

```bash
# Restore the admin editing key
op document get "sops-nix age default key" > ~/.config/sops/admin-keys.txt
chmod 600 ~/.config/sops/admin-keys.txt

# Restore a host key
op document get "sops-nix age key - coruscant" \
  > ~/.config/sops/age/host-keys/coruscant.txt
chmod 600 ~/.config/sops/age/host-keys/coruscant.txt
```

If a key has no backup and all copies are lost, generate a replacement and
follow [Rotating a Host Key](#rotating-a-host-key). The secret *values* remain
readable from any other recipient (e.g. the admin key) while you migrate.

> **This is why keeping backups is critical.**

## Secret Scanning

Pre-commit runs [gitleaks](https://gitleaks.io/) on staged changes, catching
plaintext credentials before they land in git history. If gitleaks flags a line
that is not actually a secret, bypass once with `git commit --no-verify` after
double-checking.

## Current Secrets

| File | Keys | Used by |
|------|------|---------|
| `endor.yaml` | `tinyfish-api-key`, `opencode-api-key` | Pi/hermes AI agents (home-manager) |
| `coruscant.yaml` / `threepio.yaml` | `ts-auth-key`, `cloudflare-api-key`, `home-assistant-external-domain`, `beszel-domain`, `alexa-notify-me-api-key` | Tailscale auth, Caddy DNS-01, HA/Caddy vhosts, Beszel, Alexa Notify Me |
| `dathomir.yaml` | `ts-auth-key` | Placeholder for future runtime secrets |
| `cloudflare.yaml` | R2 endpoint/keys/bucket, `restic-password` | Restic backups (`home-assistant/restic.nix`) |
| `oci.yaml` | OCI + OpenTofu state credentials | CI deploy workflow only |

## Reference

- [SOPS documentation](https://getsops.io/docs/)
- [sops-nix README](https://github.com/Mic92/sops-nix)
- [age specification](https://age-encryption.org/v1)
