# Scripts Directory

This directory contains utility scripts for the Nix configuration.

## Files

- `setup-work-ssh.sh` - Configure separate SSH keys for work repositories
- `setup-yubikey-sudo.sh` - Configure YubiKey for sudo authentication
- `README.md` - This file

## Auto-Update Service

The automatic update functionality has been moved to `modules/darwin/auto-update.nix` as a nix-darwin launchd service.

### How It Works

- **Schedule**: Runs daily at 10:00 AM
- **Function**: Checks if `flake.lock` has changes on `origin/main`
- **Notification**: Sends persistent macOS notification when updates are available
- **Action Required**: You manually run `just switch` to apply updates

### Checking Service Status

```bash
just auto-update-status
```

### Manual Trigger

```bash
launchctl start nix-config-auto-update
```

### View Logs

```bash
tail -f /tmp/nix-darwin-update.log
```

### Features

- Only notifies on `flake.lock` changes (dependency updates)
- Waits for network availability
- Persistent notifications (stay until clicked)
- Click notification to open Terminal
- No automatic rebuild (avoids sudo/Touch ID issues)

## SSH Configuration

### Work SSH Setup

To use separate SSH keys for work repositories:

```bash
just setup-work-ssh
```

This configures automatic SSH key selection based on repository path.

### YubiKey Sudo Setup

To enable YubiKey for sudo authentication:

```bash
./scripts/setup-yubikey-sudo.sh
```

## Legacy Auto-Update

The previous standalone auto-update scripts have been removed in favor of the nix-darwin managed service. The old implementation included:

- `auto-update.sh` - Complex bash script with backup/rollback
- `auto-update.conf` - Configuration file

These have been replaced with a simpler, more reliable notification-only approach.
