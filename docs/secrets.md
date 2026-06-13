# Secrets Management

This configuration uses [SOPS](https://getsops.io/) with
[age](https://age-encryption.org/) keys to encrypt secrets at rest.
SOPS-encrypted files are safe to commit to git — only holders of the age private
key can decrypt them.

The NixOS integration is provided by
[sops-nix](https://github.com/Mic92/sops-nix);
the macOS integration uses the sops-nix darwin module.

## How It Works

```text
.sops.yaml                    ← lists which age public keys can decrypt which files
secrets/default.yaml          ← SOPS-encrypted YAML committed to git
~/.config/sops/age/keys.txt   ← your age private key (NEVER commit this)
/var/lib/sops-nix/key.txt     ← age private key on the NixOS host
```

At activation time, sops-nix decrypts `secrets/default.yaml` and writes each
secret as a file under `/run/secrets/` (mode 0400 by default, owned by the
requesting service user).

## Prerequisites

```bash
# Install sops and age via nix shell (or add to your packages)
nix shell nixpkgs#sops nixpkgs#age
```

## Generating Your age Key

Run once per machine that needs to encrypt or decrypt secrets:

```bash
just init-sops
```

This creates `~/.config/sops/age/keys.txt` if it does not exist and prints the
public key. **Store the private key somewhere safe** (see
[Backing Up Your Key](#backing-up-your-age-key)).

## Adding Your Public Key to `.sops.yaml`

After generating a key, add the public key to `.sops.yaml`:

```yaml
keys:
  - &admin age1sgfy6dm4jg72eqx2rw0003cxrt8rkr6q0pp395djh99jwsulw52sc5pv7l
  - &new-machine age1<your-public-key-here>
creation_rules:
  - path_regex: secrets/.*
    key_groups:
      - age:
          - *admin
          - *new-machine   # add this line
```

Then re-encrypt all secrets so the new key can decrypt them:

```bash
just edit-secrets             # opens the file in $EDITOR; save without changes to trigger re-encryption
# or explicitly:
nix shell nixpkgs#sops nixpkgs#age -c sops updatekeys secrets/default.yaml
```

## Creating a New Secret

1. Open the secrets file in your editor:

   ```bash
   just edit-secrets
   ```

   This runs `sops secrets/default.yaml`, which decrypts the file, opens
   `$EDITOR`, and re-encrypts on save.

2. Add a new key:

   ```yaml
   my-new-secret: "the secret value"
   ```

3. Save and close. SOPS re-encrypts automatically.

4. Reference the secret in a Nix module:

   ```nix
   sops.secrets.my-new-secret = { };

   # Then use config.sops.secrets.my-new-secret.path in services
   ```

## Editing an Existing Secret

```bash
just edit-secrets
# Edit the value in $EDITOR, save, and close.
```

## Rotating the age Key

Use this procedure when a machine is compromised or when removing a key.

1. Generate a new key on the new/replacement machine:

   ```bash
   just init-sops
   ```

2. Update `.sops.yaml` — add the new public key and remove the old one.

3. Re-encrypt all secrets with the new key set:

   ```bash
   nix shell nixpkgs#sops nixpkgs#age -c sops updatekeys secrets/default.yaml
   ```

4. Commit `.sops.yaml` and `secrets/default.yaml`.

5. Deploy the updated config to all affected hosts:

   ```bash
   just switch          # Darwin
   just nixos-deploy    # NixOS (coruscant)
   ```

6. Revoke/delete the old private key from any machine that should no longer have
   access.

## Recovering Access

If you lose your age private key but have it backed up in 1Password:

```bash
# Restore from 1Password (requires 1Password CLI)
op document get "sops-nix age key" > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

If all private keys are lost and no backup exists, you must:

1. Generate a new age key (`just init-sops`).
2. Update `.sops.yaml` with the new public key.
3. Manually re-create all secrets (`just edit-secrets` — the file will be blank
   or unreadable; type the values from memory/other sources).
4. Re-encrypt with the new key set.

> **This is why keeping a backup is critical.** See below.

## Adding a New Machine

1. Generate an age key on the new machine:

   ```bash
   just init-sops
   # Copy the printed public key
   ```

2. Add the new public key to `.sops.yaml` under `keys` and under the relevant
   `key_groups` entry (see [Adding Your Public Key](#adding-your-public-key-to-sopsyaml)).

3. Re-encrypt secrets so the new machine can decrypt them:

   ```bash
   nix shell nixpkgs#sops nixpkgs#age -c sops updatekeys secrets/default.yaml
   ```

4. Commit `.sops.yaml` and `secrets/default.yaml`.

5. Copy the age private key to the new NixOS host (if applicable):

   ```bash
   # For NixOS hosts — copy key before running nixos-anywhere
   mkdir -p nixos-files/var/lib/sops-nix
   cp ~/.config/sops/age/keys.txt nixos-files/var/lib/sops-nix/key.txt
   # Then: just nixos-init
   ```

   Or for an already-running NixOS host:

   ```bash
   scp ~/.config/sops/age/keys.txt root@<host>:/var/lib/sops-nix/key.txt
   ```

6. Deploy the updated configuration.

## Backing Up Your age Key

### Option A — 1Password (recommended)

```bash
just backup-key
```

This stores `~/.config/sops/age/keys.txt` as a document in 1Password with the
tag `sops-nix,age-key`. Restore with:

```bash
op document get "sops-nix age key" > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

### Option B — Encrypted file / USB drive

```bash
# Encrypt the key with a passphrase before storing
age -p ~/.config/sops/age/keys.txt > ~/age-key-backup.age
# Store age-key-backup.age on an encrypted USB drive or secure cloud storage
```

To restore:

```bash
age -d ~/age-key-backup.age > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

## SSH Key as age Key (Optional)

You can derive an age key from your existing SSH ed25519 key, so that the same
key pair serves both purposes:

```bash
nix shell nixpkgs#ssh-to-age -c \
  ssh-to-age -private-key -i ~/.ssh/id_ed25519 \
  -o ~/.config/sops/age/keys.txt
```

The corresponding public key:

```bash
nix shell nixpkgs#ssh-to-age -c \
  ssh-to-age < ~/.ssh/id_ed25519.pub
```

Use this public key in `.sops.yaml`. If you do this, your age key backup is
effectively your SSH key backup.

## Current Secrets

| Key | Used by |
|-----|---------|
| `ts-auth-key` | Tailscale pre-auth key (`coruscant/base.nix`) |
| `home-assistant-external-domain` | HA `configuration.yaml` template, Caddy vhost |
| `cloudflare-api-key` | Caddy DNS-01 ACME challenge (`coruscant/caddy.nix`) |

## Reference

- [SOPS documentation](https://getsops.io/docs/)
- [sops-nix README](https://github.com/Mic92/sops-nix)
- [age specification](https://age-encryption.org/v1)
