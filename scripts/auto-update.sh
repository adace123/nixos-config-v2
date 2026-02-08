#!/bin/bash
set -euo pipefail

# Get dynamic paths
REPO_DIR="$(cd "$(dirname "$(realpath "${0%/*}")")" && pwd)"
LOG_FILE="${HOME}/.local/share/nix-config-auto-update.log"
BACKUP_DIR="${HOME}/.local/share/nix-config-backups"
CURRENT_COMMIT_FILE="${HOME}/.local/share/nix-config-current-commit"

# Create directories if they don't exist
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$BACKUP_DIR")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

send_notification() {
  local title="$1"
  local message="$2"
  local sound="${3:-default}"
  osascript -e "display notification \"$message\" with title \"$title\" sound name \"$sound\""
}

# Save current commit for rollback
save_current_commit() {
  git rev-parse HEAD > "$CURRENT_COMMIT_FILE" 2>/dev/null || true
}

# Restore from backup
restore_backup() {
  local backup_file="$1"
  if [ -f "$backup_file" ]; then
    log "Restoring from backup: $backup_file"
    sudo /run/current-system/sw/bin/darwin-rebuild switch --flake "$backup_file"
  fi
}

# Run command with timeout
run_with_timeout() {
  local timeout_seconds="$1"
  local command="$2"
  local description="$3"
  
  log "Running $description (timeout: ${timeout_seconds}s)..."
  if timeout "$timeout_seconds" bash -c "$command"; then
    log "$description completed successfully"
    return 0
  else
    local exit_code=$?
    if [ $exit_code -eq 124 ]; then
      log "ERROR: $description timed out after ${timeout_seconds}s"
    else
      log "ERROR: $description failed with exit code $exit_code"
    fi
    return $exit_code
  fi
}

# Verify git signature
verify_git_signature() {
  local commit="$1"
  if git verify-commit "$commit" >/dev/null 2>&1; then
    log "Git signature verified for commit $commit"
    return 0
  else
    log "WARNING: No valid git signature for commit $commit - rejecting"
    return 1
  fi
}

# Time window check - only run within 15 minutes of 9:00 AM on weekdays
current_hour=$(date +%H)
current_minute=$(date +%M)
current_weekday=$(date +%u)  # 1=Monday, 5=Friday

if [ "$current_weekday" -gt 5 ] || [ "$current_weekday" -lt 1 ]; then
  log "Skipping: Weekend (weekday $current_weekday)"
  exit 0
fi

if [ "$current_hour" -ne 9 ] || [ "$current_minute" -gt 15 ]; then
  log "Skipping: Not in 9:00-9:15 AM window (current: $current_hour:$current_minute, weekday: $current_weekday)"
  exit 0
fi

cd "$REPO_DIR" || {
  log "ERROR: Failed to change to $REPO_DIR"
  send_notification "Nix Config Update" "Failed to access config directory" "Basso"
  exit 1
}

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  log "ERROR: Not a git repository"
  send_notification "Nix Config Update" "Not a git repository" "Basso"
  exit 1
fi

# Verify git signatures if available
if git log -1 --show-signature 2>/dev/null | grep -q "Good signature"; then
  log "Git commit verified: Good signature"
else
  log "WARNING: No git signature found, continuing anyway"
fi

log "Checking for updates..."

if ! run_with_timeout 30 "git fetch origin main" "git fetch"; then
  log "ERROR: Failed to fetch updates"
  send_notification "Nix Config Update" "Failed to fetch updates" "Basso"
  exit 1
fi

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" = "$REMOTE" ]; then
  log "Already up to date"
  exit 0
fi

# Verify signature of remote commit before pulling
if ! verify_git_signature "$REMOTE"; then
  log "ERROR: Remote commit signature verification failed"
  send_notification "Nix Config Update" "Commit signature verification failed" "Basso"
  exit 1
fi

log "Updates available: $LOCAL -> $REMOTE"

# Create backup before applying changes
save_current_commit
backup_file="$BACKUP_DIR/$(date +%Y%m%d_%H%M%S)_${LOCAL:0:7}.nix"
if ! cp -r . "$backup_file"; then
  log "WARNING: Failed to create backup, continuing anyway"
fi

log "Pulling latest changes..."
if ! run_with_timeout 60 "git pull origin main" "git pull"; then
  log "ERROR: Failed to pull changes"
  
  # Try to restore from backup if available
  if [ -f "$CURRENT_COMMIT_FILE" ]; then
    prev_commit=$(cat "$CURRENT_COMMIT_FILE")
    if git reset --hard "$prev_commit" 2>&1 | tee -a "$LOG_FILE"; then
      log "Successfully restored to previous commit"
      send_notification "Nix Config Update" "Reverted to previous commit" "Basso"
    else
      log "Failed to restore previous commit"
      send_notification "Nix Config Update" "Update failed and rollback unsuccessful" "Basso"
    fi
  else
    send_notification "Nix Config Update" "Update failed - manual resolution needed" "Basso"
  fi
  exit 1
fi

log "Running darwin-rebuild switch..."
if run_with_timeout 300 "sudo /run/current-system/sw/bin/darwin-rebuild switch --flake ." "darwin-rebuild switch"; then
  log "SUCCESS: Configuration updated and applied"
  send_notification "Nix Config" "Configuration updated successfully ✓" "Glass"
else
  log "ERROR: darwin-rebuild switch failed"
  
  # Attempt to restore from backup
  if [ -d "$backup_file" ]; then
    restore_backup "$backup_file"
  fi
  
  send_notification "Nix Config Update" "Switch failed - check logs" "Basso"
  exit 1
fi
