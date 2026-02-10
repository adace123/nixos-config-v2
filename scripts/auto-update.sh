#!/bin/bash
set -euo pipefail

# Load configuration file
SCRIPT_DIR="$(cd "$(dirname "$(realpath "${0%/*}")")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/auto-update.conf}"

# Load config file if it exists
if [ -f "$CONFIG_FILE" ]; then
  # Source config file, allowing overrides by environment variables
  set -a
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
  set +a
fi

# Configuration with defaults (can be overridden by environment variables)
# Note: CURRENT_LOG_LEVEL will be set after log_level_to_number function is defined
CURRENT_LOG_LEVEL=""
DEFAULT_TIMEOUT_FETCH="${TIMEOUT_FETCH:-30}"
DEFAULT_TIMEOUT_PULL="${TIMEOUT_PULL:-60}"
DEFAULT_TIMEOUT_BUILD="${TIMEOUT_BUILD:-300}"
DEFAULT_TIMEOUT_FLAKE_CHECK="${TIMEOUT_FLAKE_CHECK:-120}"
DEFAULT_TIME_WINDOW_MINUTES="${TIME_WINDOW_MINUTES:-15}"
DEFAULT_MIN_DISK_SPACE_MB="${MIN_DISK_SPACE_MB:-1024}"
DEFAULT_ENABLE_FLAKE_CHECK="${ENABLE_FLAKE_CHECK:-true}"
DEFAULT_ENABLE_BACKUP="${ENABLE_BACKUP:-true}"
DEFAULT_ENABLE_NOTIFICATIONS="${ENABLE_NOTIFICATIONS:-true}"
DEFAULT_NOTIFICATION_SOUND="${NOTIFICATION_SOUND:-default}"
DEFAULT_CHECK_NETWORK="${CHECK_NETWORK:-true}"
DEFAULT_GIT_REMOTE="${GIT_REMOTE:-origin}"
DEFAULT_GIT_BRANCH="${GIT_BRANCH:-main}"
DEFAULT_DRY_RUN="${DRY_RUN:-false}"
DEFAULT_DEBUG_MODE="${DEBUG_MODE:-false}"

# Parse command line arguments
FORCE_RUN=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --force)
      FORCE_RUN=true
      shift
      ;;
    --dry-run)
      DEFAULT_DRY_RUN=true
      shift
      ;;
    --debug)
      DEFAULT_DEBUG_MODE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --force     Force run outside of scheduled time window"
      echo "  --dry-run   Simulate update without applying changes"
      echo "  --debug     Enable debug logging"
      echo "  -h, --help  Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Debug mode: set log level to DEBUG if enabled
if [ "$DEFAULT_DEBUG_MODE" = "true" ]; then
  CURRENT_LOG_LEVEL=$(log_level_to_number "DEBUG")
fi

# Dynamic paths
REPO_DIR="$(cd "$(dirname "$(realpath "${0%/*}")")" && pwd)"
LOG_FILE="${HOME}/.local/share/nix-config-auto-update.log"
BACKUP_DIR="${HOME}/.local/share/nix-config-backups"
CURRENT_COMMIT_FILE="${HOME}/.local/share/nix-config-current-commit"
NIX_LOGO_PATH="${REPO_DIR}/assets/nix-logo.png"

# State tracking
BACKUP_FILE=""
ROLLBACK_ENABLED=true

# Create directories if they don't exist
mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR"

# Log levels
readonly LOG_ERROR=0
readonly LOG_WARN=1
readonly LOG_INFO=2
readonly LOG_DEBUG=3

CURRENT_LOG_LEVEL=$LOG_INFO

log_level_to_number() {
  case "$1" in
    "ERROR") echo $LOG_ERROR ;;
    "WARN") echo $LOG_WARN ;;
    "INFO") echo $LOG_INFO ;;
    "DEBUG") echo $LOG_DEBUG ;;
    *) echo $LOG_INFO ;;
  esac
}

log() {
  local level="$1"
  local message="$2"
  local level_num
  level_num=$(log_level_to_number "$level")
  
  if [ "$level_num" -le "$CURRENT_LOG_LEVEL" ]; then
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$level] $message"
    echo "$log_entry" | tee -a "$LOG_FILE"
  fi
}

log_error() { log "ERROR" "$1"; }
log_warn() { log "WARN" "$1"; }
log_info() { log "INFO" "$1"; }
log_debug() { log "DEBUG" "$1"; }

# Initialize CURRENT_LOG_LEVEL based on configuration
CURRENT_LOG_LEVEL=$(log_level_to_number "${LOG_LEVEL:-INFO}")

send_notification() {
  local title="$1"
  local message="$2"
  local sound="${3:-$DEFAULT_NOTIFICATION_SOUND}"

  if [ "$DEFAULT_ENABLE_NOTIFICATIONS" != "true" ]; then
    log_debug "Notifications disabled, skipping: $title - $message"
    return 0
  fi

  log_debug "Sending notification: $title - $message"

  # Prepend Nix snowflake emoji to title for visual identification
  local nix_title="❄️ $title"

  # Use Nix logo if available via terminal-notifier (if installed)
  if command -v terminal-notifier >/dev/null 2>&1 && [ -f "$NIX_LOGO_PATH" ]; then
    log_debug "Using terminal-notifier with logo: $NIX_LOGO_PATH"
    # Use contentImage to show logo within notification (more reliable than appIcon)
    terminal-notifier -title "$title" -message "$message" -contentImage "$NIX_LOGO_PATH" -sound "$sound" 2>/dev/null || \
    osascript -e "display notification \"$message\" with title \"$nix_title\" sound name \"$sound\"" 2>/dev/null || true
  else
    log_debug "Using osascript for notification"
    osascript -e "display notification \"$message\" with title \"$nix_title\" sound name \"$sound\"" 2>/dev/null || true
  fi
}

# Cleanup function for trap
cleanup() {
  local exit_code=$?
  if [ $exit_code -ne 0 ] && [ "$ROLLBACK_ENABLED" = "true" ] && [ -n "$BACKUP_FILE" ] && [ -d "$BACKUP_FILE" ]; then
    log_warn "Cleanup triggered, attempting to restore backup..."
    restore_backup "$BACKUP_FILE" || log_error "Failed to restore backup during cleanup"
  fi
  exit $exit_code
}

# Set up trap for cleanup
trap cleanup EXIT INT TERM

# Save current commit for rollback
save_current_commit() {
  git rev-parse HEAD > "$CURRENT_COMMIT_FILE" 2>/dev/null || true
}

# Clean up old backups
cleanup_old_backups() {
  local max_days="${MAX_BACKUP_DAYS:-7}"
  if [ ! -d "$BACKUP_DIR" ]; then
    return 0
  fi
  
  log_debug "Cleaning up backups older than $max_days days"
  local deleted_count
  deleted_count=$(find "$BACKUP_DIR" -name "*.nix" -type d -mtime +"$max_days" -print | wc -l)
  if [ "$deleted_count" -gt 0 ]; then
    find "$BACKUP_DIR" -name "*.nix" -type d -mtime +"$max_days" -exec rm -rf {} + 2>/dev/null || true
    log_info "Cleaned up $deleted_count old backup(s)"
  fi
}

# Clean up old log files
cleanup_old_logs() {
  # Keep last 7 days of logs
  if [ -f "$LOG_FILE" ]; then
    log_debug "Rotating log file (keeping last 7 days)"
    tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE" || true
  fi
}

# Restore from backup
restore_backup() {
  local backup_file="$1"
  if [ -d "$backup_file" ]; then
    log_warn "Restoring from backup: $backup_file"
    if sudo /run/current-system/sw/bin/darwin-rebuild switch --flake "$backup_file"; then
      log_info "Successfully restored from backup"
      send_notification "Nix Config Update" "Successfully restored from backup" "Glass"
      return 0
    else
      log_error "Failed to restore from backup"
      send_notification "Nix Config Update" "Failed to restore from backup" "Basso"
      return 1
    fi
  else
    log_error "Backup file not found: $backup_file"
    return 1
  fi
}

# Pre-flight checks
run_preflight_checks() {
  log_info "Running pre-flight checks..."
  
  # Check if dry run
  if [ "$DEFAULT_DRY_RUN" = "true" ]; then
    log_info "DRY RUN: Skipping actual pre-flight checks"
    return 0
  fi
  
  # Check disk space
  local available_space
  available_space=$(df -m "$HOME" | awk 'NR==2 {print $4}')
  if [ "$available_space" -lt "$DEFAULT_MIN_DISK_SPACE_MB" ]; then
    log_error "Insufficient disk space: ${available_space}MB available, ${DEFAULT_MIN_DISK_SPACE_MB}MB required"
    return 1
  fi
  log_debug "Disk space check passed: ${available_space}MB available"
  
  # Check network connectivity
  if [ "$DEFAULT_CHECK_NETWORK" = "true" ]; then
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
      log_warn "Network connectivity check failed, continuing anyway"
    else
      log_debug "Network connectivity check passed"
    fi
  else
    log_debug "Network connectivity check disabled by configuration"
  fi
  
  # Check if we can access required commands
  local required_commands=("git" "sudo")
  if [ "$DEFAULT_ENABLE_FLAKE_CHECK" = "true" ]; then
    required_commands+=("nix")
  fi
  # Note: timeout is optional - script has fallback for macOS
  for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log_error "Required command not found: $cmd"
      return 1
    fi
  done
  log_debug "Required commands check passed"
  
  log_info "Pre-flight checks completed successfully"
  return 0
}

# Run command with timeout (cross-platform implementation)
run_with_timeout() {
  local timeout_seconds="$1"
  local command="$2"
  local description="$3"

  log_info "Running $description (timeout: ${timeout_seconds}s)..."
  log_debug "Command: $command"

  # Try different timeout methods
  local exit_code=0

  if command -v gtimeout >/dev/null 2>&1; then
    # GNU timeout (from coreutils)
    gtimeout "$timeout_seconds" bash -c "$command" || exit_code=$?
  elif command -v timeout >/dev/null 2>&1; then
    # Native timeout (Linux)
    timeout "$timeout_seconds" bash -c "$command" || exit_code=$?
  else
    # Fallback: run without timeout on macOS
    log_warn "timeout command not available, running without timeout"
    bash -c "$command" || exit_code=$?
    # Fake timeout exit code for consistency
    if [ $exit_code -eq 124 ]; then
      exit_code=1
    fi
  fi

  if [ $exit_code -eq 0 ]; then
    log_info "$description completed successfully"
    return 0
  elif [ $exit_code -eq 124 ]; then
    log_error "$description timed out after ${timeout_seconds}s"
    return $exit_code
  else
    log_error "$description failed with exit code $exit_code"
    return $exit_code
  fi
}

# Time window check - only run within configured time window of 9:00 AM on weekdays
# Can be overridden with --force flag
current_hour=$(date +%H)
current_minute=$(date +%M)
current_weekday=$(date +%u)  # 1=Monday, 5=Friday

if [ "$FORCE_RUN" = "true" ]; then
  log_warn "Force run enabled: Skipping time window check"
else
  if [ "$current_weekday" -gt 5 ] || [ "$current_weekday" -lt 1 ]; then
    log_info "Skipping: Weekend (weekday $current_weekday)"
    exit 0
  fi

  if [ "$current_hour" -ne 9 ] || [ "$current_minute" -gt "$DEFAULT_TIME_WINDOW_MINUTES" ]; then
    log_info "Skipping: Not in 9:00-9:${DEFAULT_TIME_WINDOW_MINUTES} AM window (current: $current_hour:$current_minute, weekday: $current_weekday)"
    exit 0
  fi
fi

log_info "Time window check passed: $current_hour:$current_minute on weekday $current_weekday"

# Run pre-flight checks
if ! run_preflight_checks; then
  send_notification "Nix Config Update" "Pre-flight checks failed" "Basso"
  exit 1
fi

cd "$REPO_DIR" || {
  log_error "Failed to change to $REPO_DIR"
  send_notification "Nix Config Update" "Failed to access config directory" "Basso"
  exit 1
}

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  log_error "Not a git repository"
  send_notification "Nix Config Update" "Not a git repository" "Basso"
  exit 1
fi

log_info "Repository check passed: $REPO_DIR"



log_info "Checking for updates..."

if ! run_with_timeout "$DEFAULT_TIMEOUT_FETCH" "git fetch $DEFAULT_GIT_REMOTE $DEFAULT_GIT_BRANCH" "git fetch"; then
  log_error "Failed to fetch updates from $DEFAULT_GIT_REMOTE/$DEFAULT_GIT_BRANCH"
  send_notification "Nix Config Update" "Failed to fetch updates" "Basso"
  exit 1
fi

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "$DEFAULT_GIT_REMOTE/$DEFAULT_GIT_BRANCH")

log_debug "Local commit: $LOCAL"
log_debug "Remote commit: $REMOTE"

if [ "$LOCAL" = "$REMOTE" ]; then
  log_info "Already up to date"
  exit 0
fi

log_info "Updates available: ${LOCAL:0:7} -> ${REMOTE:0:7}"

# Create backup before applying changes
save_current_commit
if [ "$DEFAULT_ENABLE_BACKUP" = "true" ]; then
  BACKUP_FILE="$BACKUP_DIR/$(date +%Y%m%d_%H%M%S)_${LOCAL:0:7}.nix"
  if ! cp -r . "$BACKUP_FILE"; then
    log_warn "Failed to create backup at $BACKUP_FILE, continuing anyway"
    BACKUP_FILE=""
    ROLLBACK_ENABLED=false
  else
    log_info "Created backup at: $BACKUP_FILE"
  fi
else
  log_info "Backup creation disabled by configuration"
  BACKUP_FILE=""
  ROLLBACK_ENABLED=false
fi

# Check if this is a dry run
if [ "$DEFAULT_DRY_RUN" = "true" ]; then
  log_info "DRY RUN: Would pull changes and rebuild, but stopping here"
  send_notification "Nix Config Update" "DRY RUN: Updates available" "Glass"
  exit 0
fi

log_info "Pulling latest changes..."
if ! run_with_timeout "$DEFAULT_TIMEOUT_PULL" "git pull $DEFAULT_GIT_REMOTE $DEFAULT_GIT_BRANCH" "git pull"; then
  log_error "Failed to pull changes"
  
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

# Run flake check before building
if [ "$DEFAULT_ENABLE_FLAKE_CHECK" = "true" ]; then
  log_info "Running flake check..."
  if ! run_with_timeout "$DEFAULT_TIMEOUT_FLAKE_CHECK" "nix flake check --all-systems" "flake check"; then
    log_error "Flake check failed, aborting update"
    send_notification "Nix Config Update" "Flake check failed" "Basso"
    exit 1
  fi
else
  log_info "Flake check disabled by configuration"
fi

log_info "Running darwin-rebuild switch..."
if run_with_timeout "$DEFAULT_TIMEOUT_BUILD" "sudo /run/current-system/sw/bin/darwin-rebuild switch --flake ." "darwin-rebuild switch"; then
  log_info "SUCCESS: Configuration updated and applied"
  send_notification "Nix Config" "Configuration updated successfully ✓" "Glass"
  
  # Clean up old backups and logs
  cleanup_old_backups
  cleanup_old_logs
  
  # Disable rollback on success
  ROLLBACK_ENABLED=false
else
  log_error "darwin-rebuild switch failed"
  
  # Attempt to restore from backup if available
  if [ -n "$BACKUP_FILE" ] && [ -d "$BACKUP_FILE" ]; then
    log_warn "Attempting to restore from backup: $BACKUP_FILE"
    restore_backup "$BACKUP_FILE" || log_error "Backup restoration failed"
  fi
  
  send_notification "Nix Config Update" "Switch failed - check logs" "Basso"
  exit 1
fi
