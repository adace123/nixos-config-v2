# Auto-Update Script Configuration

This directory contains the Nix configuration auto-update system.

## Files

- `auto-update.sh` - Main auto-update script
- `auto-update.conf` - Configuration file with all settings and defaults

## Configuration

The script can be configured in three ways (in order of precedence):

1. **Environment variables** - Highest priority
2. **Configuration file** (`auto-update.conf`) - Medium priority
3. **Hardcoded defaults** - Lowest priority

### Environment Variables

You can override any configuration setting by setting environment variables:

```bash
export LOG_LEVEL=DEBUG
export TIMEOUT_BUILD=600
export DRY_RUN=true
./auto-update.sh
```

### Configuration File

Edit `auto-update.conf` to change default settings. The file includes comments explaining each option.

## Key Improvements Made

### Security

- **Consistent Git Signature Verification** - Fixed inconsistent verification, now properly verifies all remote commits
- **Flake Check Integration** - Runs `nix flake check --all-systems` before building (configurable)
- **Pre-flight Security Checks** - Validates environment and dependencies

### Reliability

- **Structured Logging** - Multiple log levels (ERROR, WARN, INFO, DEBUG) with timestamps
- **Trap-based Cleanup** - Automatic rollback on script failure or interruption
- **Improved Rollback** - Better error handling and backup restoration
- **Pre-flight Checks** - Disk space, network, and command availability validation

### Performance & Maintainability

- **Configurable Timeouts** - Appropriate timeouts for different operations
- **Backup Management** - Automatic cleanup of old backups
- **Log Rotation** - Prevents log files from growing too large
- **Dry Run Mode** - Test mode that simulates operations without making changes

### Configuration Management

- **External Config File** - All settings can be modified without editing the script
- **Environment Variable Support** - Runtime overrides for testing and customization
- **Default Values** - Sensible defaults that work out of the box

## Usage

### Basic Usage

```bash
./scripts/auto-update.sh
```

### Dry Run (Test Mode)

```bash
DRY_RUN=true ./scripts/auto-update.sh
```

### Debug Mode

```bash
DEBUG_MODE=true ./scripts/auto-update.sh
```

### Custom Configuration

```bash
CONFIG_FILE=/path/to/custom.conf ./scripts/auto-update.sh
```

## Log Files

- **Main log**: `~/.local/share/nix-config-auto-update.log`
- **stdout**: `~/.local/share/nix-config-auto-update.stdout.log` (from launchd)
- **stderr**: `~/.local/share/nix-config-auto-update.stderr.log` (from launchd)

## Backup Management

- Backups are stored in `~/.local/share/nix-config-backups/`
- Format: `YYYYMMDD_HHMMSS_COMMIT.nix`
- Automatic cleanup of backups older than 7 days (configurable)
- Rollback automatically attempted on failure

## Security Notes

- Git signature verification is enabled by default
- Flake validation runs before building
- Privilege escalation is properly validated
- All operations are logged for audit purposes

## Troubleshooting

### Enable Debug Logging

```bash
LOG_LEVEL=DEBUG ./scripts/auto-update.sh
```

### Check Recent Logs

```bash
tail -f ~/.local/share/nix-config-auto-update.log
```

### Manual Rollback

```bash
cd ~/.local/share/nix-config-backups
# Find the backup you want to restore
sudo /run/current-system/sw/bin/darwin-rebuild switch --flake ./20241209_090000_abc1234.nix
```

## Service Status

Check the launchd service status:

```bash
launchctl list | grep nix-config-auto-update
```
