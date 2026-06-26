# nixos-config-v2

Personal Nix flake managing a macOS workstation and a Raspberry Pi 4 home
server. Uses [nix-darwin](https://github.com/LnL7/nix-darwin),
[home-manager](https://nix-community.github.io/home-manager/), and
[SOPS](https://getsops.io/) for secrets.

## Architecture

```text
flake.nix
├── Darwin  (aarch64-darwin)
│   └── endor          — Apple Silicon Mac
│       └── home-manager (user: aaron)
│           ├── shell / CLI tools / dev environments
│           ├── Neovim (nvf), Zed, Ghostty, Zellij
│           └── AI tools (Claude, Hermes, opencode)
└── NixOS   (aarch64-linux)
    └── coruscant      — Raspberry Pi 4 home server
        ├── Home Assistant  (podman container, port 8123)
        ├── Mosquitto       (MQTT broker, port 1883)
        ├── Zigbee2MQTT     (Zigbee bridge, port 8091)
        ├── ESPHome         (ESP device manager, port 6052)
        ├── Beszel Hub      (server monitoring, port 8090)
        └── Caddy           (HTTPS reverse proxy, Cloudflare DNS-01)
```

### How the pieces fit together

| Layer | Tool | Purpose |
|-------|------|---------|
| System (macOS) | nix-darwin | System packages, macOS defaults, Homebrew, Touch ID sudo |
| User (macOS) | home-manager | Shell, CLI tools, editors, dev environments |
| System (Linux) | NixOS | Pi kernel, services, firewall, Tailscale, SOPS secrets |
| Secrets | SOPS + age | Encrypted YAML committed to git; decrypted at activation |
| Remote access | Tailscale | Secure SSH and service access from anywhere |

### Shared modules

```text
modules/
├── darwin/       # nix-darwin system config (macOS)
├── home/         # home-manager user config (macOS)
└── nixos/
    ├── common.nix              # shared NixOS settings (SSH, firewall, NTP, GC…)
    ├── beszel.nix              # Beszel monitoring
    ├── base.nix                # hostname, SOPS, Tailscale auth
    ├── caddy.nix               # Caddy reverse proxy (Cloudflare DNS)
    ├── installer.nix           # SD-card installer image
    ├── ssd.nix                 # Disko SSD partition layout + boot config
    └── home-assistant/         # HA container, MQTT, Zigbee2MQTT, ESPHome

Host identity is now data-driven via `hosts/`, where each machine declares only
its identity and shared modules provide the behavior:

```text
hosts/
├── endor/           # Darwin workstation identity (hostname, user, system)
└── coruscant/       # NixOS Raspberry Pi identity (hostname, system)
```

## Quick Start

### macOS (first time)

```bash
# 1. Install Nix (Determinate installer)
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install

# 2. Clone and bootstrap
git clone https://github.com/adace123/nixos-config-v2
cd nixos-config-v2
./bootstrap.sh
```

Or manually:

```bash
nix profile install nixpkgs#just
just switch HOST=endor
```

### NixOS / Raspberry Pi (first time)

```bash
# Prepare age key for secrets decryption on the Pi
mkdir -p nixos-files/var/lib/sops-nix
cp ~/.config/sops/age/keys.txt nixos-files/var/lib/sops-nix/key.txt

# Boot Pi from installer SD card, then:
just nixos-init
```

See [docs/nixos.md](docs/nixos.md) for the full provisioning walkthrough.

## Common Commands

| Task | Command |
|------|---------|
| Apply macOS config | `just switch` |
| Validate (flake check + build) | `just check` |
| Deploy to Pi | `just nixos-deploy` |
| Edit secrets | `just edit-secrets` |
| Init age key | `just init-sops` |
| Back up age key to 1Password | `just backup-key` |
| Update all flake inputs | `just update` |
| Garbage-collect | `just clean` |

## Secrets

Secrets use SOPS + age encryption. The encrypted file `secrets/default.yaml`
is safe to commit. The private key lives at `~/.config/sops/age/keys.txt` on
macOS and `/var/lib/sops-nix/key.txt` on the Pi.

See [docs/secrets.md](docs/secrets.md) for the full workflow: creating,
editing, rotating keys, recovering access, adding a new machine, and backups.

## Documentation

| Doc | Contents |
|-----|---------|
| [docs/darwin.md](docs/darwin.md) | macOS setup, packages, customisation, troubleshooting |
| [docs/nixos.md](docs/nixos.md) | Pi provisioning, services, remote deployment |
| [docs/home-assistant.md](docs/home-assistant.md) | HA layout, services, intended future structure |
| [docs/secrets.md](docs/secrets.md) | Full secrets workflow |
| [docs/deployment.md](docs/deployment.md) | All deployment commands, auto-update, GC |

## Repository Structure

```text
.
├── flake.nix                 # Inputs and flake-parts wiring
├── flake.lock                # Locked dependency versions
├── flake-parts/
│   ├── darwin.nix            # Darwin outputs built from hosts/ metadata
│   ├── nixos.nix             # NixOS outputs built from hosts/ metadata
│   └── pre-commit.nix        # Pre-commit hooks
├── modules/
│   ├── darwin/               # nix-darwin system modules
│   ├── home/                 # home-manager user modules
│   └── nixos/
│       ├── common.nix
│       ├── beszel.nix
│       ├── base.nix
│       ├── caddy.nix
│       ├── installer.nix
│       ├── ssd.nix
│       └── home-assistant/
├── secrets/
│   └── default.yaml          # SOPS-encrypted secrets
├── scripts/                  # Helper shell scripts
├── bootstrap.sh              # First-time macOS setup
├── justfile                  # All runnable commands
└── docs/                     # Focused documentation
```

## Resources

- [nix-darwin documentation](https://github.com/LnL7/nix-darwin)
- [home-manager manual](https://nix-community.github.io/home-manager/)
- [Nix language guide](https://nix.dev/manual/nix/stable/language/)
- [Nixpkgs search](https://search.nixos.org/packages)
- [sops-nix](https://github.com/Mic92/sops-nix)
