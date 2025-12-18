#!/usr/bin/env bash
set -euo pipefail

# Enhanced Steam Cache Relocator with improved robustness
# Version: 2.1

readonly SCRIPT_NAME=$(basename "$0")
readonly LOCK_FILE_NAME=".steam_cache_relocator.lock"

log_level="${LOG_LEVEL:-INFO}"

# Colors for better readability if stderr is a terminal
if [[ -t 2 ]]; then
    readonly C_RED='\033[0;31m'
    readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[0;33m'
    readonly C_BLUE='\033[0;34m'
    readonly C_RESET='\033[0m'
else
    readonly C_RED=''
    readonly C_GREEN=''
    readonly C_YELLOW=''
    readonly C_BLUE=''
    readonly C_RESET=''
fi

log() {
  local level="${1:-INFO}"
  shift
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local color="$C_RESET"
  
  case "$level" in
    INFO)  color="$C_BLUE" ;;
    WARN)  color="$C_YELLOW" ;;
    ERROR) color="$C_RED" ;;
    DEBUG) color="$C_RESET" ;;
  esac

  printf '[%s] [%b%s%b] %s\n' "$timestamp" "$color" "$level" "$C_RESET" "$*" >&2
}

log_info() {
  log "INFO" "$@"
}

log_warn() {
  log "WARN" "$@"
}

log_error() {
  log "ERROR" "$@"
}

log_debug() {
  [[ "$log_level" == "DEBUG" ]] && log "DEBUG" "$@" || true
}

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [OPTIONS] [main_steam_dir]

Relocate or restore shader and Proton caches between secondary Steam
libraries and the primary Steam directory (default: \$HOME/.local/share/Steam).

Options:
  --undo           Restore directories that were previously symlinked by this script
  --dry-run        Show what would be done without making changes
  --no-progress    Disable rsync progress output
  --force          Skip Steam running check (use with caution)
  --no-space-check Skip disk space verification
  --debug          Enable debug logging
  -h, --help       Show this help message

Environment Variables:
  LOG_LEVEL        Set to DEBUG for verbose output

Safety Features:
  - Checks if Steam is running (use --force to override)
  - Verifies sufficient disk space before operations
  - Uses lock file to prevent concurrent execution
  - Creates state file for safe undo operations
  - Validates all paths and permissions before proceeding

Examples:
  $SCRIPT_NAME                    # Relocate caches to main library
  $SCRIPT_NAME --dry-run          # Preview changes without applying
  $SCRIPT_NAME --undo             # Restore original structure
  $SCRIPT_NAME ~/.steam/steam     # Use custom Steam directory

USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "Required command '$1' not found. Install it and retry."
    exit 1
  fi
}

# Check if Steam is currently running
is_steam_running() {
  if pgrep -x "steam" >/dev/null 2>&1 || pgrep -x "steamwebhelper" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Get disk usage for a directory in bytes
get_dir_size() {
  local dir="$1"
  [[ -d "$dir" ]] || { echo "0"; return; }
  du -sb "$dir" 2>/dev/null | awk '{print $1}' || echo "0"
}

# Get available space on filesystem containing the path
get_available_space() {
  local path="$1"
  df -B1 "$path" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0"
}

# Check if we have enough space to relocate
check_disk_space() {
  local src="$1" dst="$2"
  local src_size avail_space margin

  src_size=$(get_dir_size "$src")
  avail_space=$(get_available_space "$dst")

  # Add 10% margin for safety
  margin=$((src_size + src_size / 10))

  if (( margin > avail_space )); then
    log_error "Insufficient space: need $margin bytes, have $avail_space bytes"
    return 1
  fi

  log_debug "Space check OK: $src_size bytes to move, $avail_space bytes available"
  return 0
}

# Convert bytes to human readable format
human_readable_size() {
  local bytes="$1"
  local units=("B" "KB" "MB" "GB" "TB")
  local unit=0
  local size=$bytes

  while (( size > 1024 && unit < 4 )); do
    size=$((size / 1024))
    ((unit++))
  done

  echo "${size}${units[$unit]}"
}

mode="relocate"
show_progress=1
dry_run=0
force_mode=0
skip_space_check=0
declare -a positional=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --undo)
      mode="undo"
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --force)
      force_mode=1
      shift
      ;;
    --no-space-check)
      skip_space_check=1
      shift
      ;;
    --debug)
      log_level="DEBUG"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      positional+=("$@")
      break
      ;;
    --no-progress)
      show_progress=0
      shift
      ;;
    -*)
      log_error "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

if [[ ${#positional[@]} -gt 1 ]]; then
  log_error "Too many arguments"
  usage
  exit 1
fi

# Validate main Steam directory
main_dir="${positional[0]:-$HOME/.local/share/Steam}"
if [[ ! -d "$main_dir" ]]; then
  alt="$HOME/.steam/steam"
  if [[ -d "$alt" ]]; then
    log_info "Using fallback directory: $alt"
    main_dir="$alt"
  else
    log_error "Steam directory not found at $main_dir or $alt. Pass it explicitly."
    exit 1
  fi
fi

main_dir=$(readlink -f "$main_dir")
steamapps_dir="$main_dir/steamapps"

if [[ ! -d "$steamapps_dir" ]]; then
  log_error "Missing steamapps directory under $main_dir"
  exit 1
fi

# Check write permissions
if [[ ! -w "$steamapps_dir" ]]; then
  log_error "No write permission for $steamapps_dir"
  exit 1
fi

# State management
state_dir="$steamapps_dir/.steam_cache_relocator"
state_file="$state_dir/state.tsv"
lock_file="$steamapps_dir/$LOCK_FILE_NAME"

# Lock file management
acquire_lock() {
  local max_wait=30
  local waited=0

  while [[ -f "$lock_file" ]]; do
    if (( waited >= max_wait )); then
      local lock_pid
      lock_pid=$(cat "$lock_file" 2>/dev/null || echo "unknown")
      log_error "Lock file exists (PID: $lock_pid). Another instance may be running."
      log_error "If you're sure no other instance is running, remove: $lock_file"
      exit 1
    fi
    log_info "Waiting for lock file to be released..."
    sleep 1
    ((waited++))
  done

  echo $$ > "$lock_file"
  log_debug "Acquired lock with PID $$"
}

release_lock() {
  if [[ -f "$lock_file" ]]; then
    local lock_pid
    lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")
    if [[ "$lock_pid" == "$$" ]]; then
      rm -f "$lock_file"
      log_debug "Released lock"
    fi
  fi
}

# Cleanup temporary files and release lock
tmp_state_file=""
declare -a tmp_item_files=()

cleanup_tmp_artifacts() {
  local exit_code=$?

  [[ -n "$tmp_state_file" && -f "$tmp_state_file" ]] && rm -f "$tmp_state_file"
  for tmp in "${tmp_item_files[@]}"; do
    [[ -f "$tmp" ]] && rm -f "$tmp"
  done

  release_lock

  if (( exit_code != 0 )); then
    log_error "Script exited with error code $exit_code"
  fi
}

trap cleanup_tmp_artifacts EXIT
trap 'log_error "Interrupted by user"; exit 130' INT TERM

# Acquire lock early
acquire_lock

# Check if Steam is running (unless forced)
if (( force_mode == 0 )); then
  if is_steam_running; then
    log_error "Steam is currently running. Please close Steam before running this script."
    log_error "If you want to proceed anyway (not recommended), use --force flag."
    exit 1
  fi
  log_info "Steam process check: OK"
else
  log_warn "Skipping Steam running check (--force mode)"
fi

# Parse library folders
library_file="$steamapps_dir/libraryfolders.vdf"
if [[ ! -f "$library_file" ]]; then
  log_error "Cannot locate $library_file"
  exit 1
fi

log_debug "Parsing Steam library folders from $library_file"

mapfile -t raw_paths < <(awk -F'"' '/"path"/ {print $4}' "$library_file")
raw_paths+=("$main_dir")

declare -A seen=()
library_paths=()

for path in "${raw_paths[@]}"; do
  [[ -n "$path" ]] || continue
  resolved=$(readlink -f "$path" 2>/dev/null || printf '%s' "$path")
  if [[ ! -d "$resolved" ]]; then
    log_warn "Skipping missing library: $resolved"
    continue
  fi
  if [[ -z ${seen[$resolved]+x} ]]; then
    seen[$resolved]=1
    library_paths+=("$resolved")
    log_debug "Found library: $resolved"
  fi
done

if [[ ${#library_paths[@]} -le 1 ]]; then
  log_info "No secondary Steam libraries detected."
  if [[ "$mode" == "undo" ]]; then
    log_info "Nothing to undo."
  fi
  exit 0
fi

log_info "Found ${#library_paths[@]} Steam libraries (including main)"

readonly CACHE_TARGETS=(shadercache compatdata)

# Validate required commands for relocate mode
if [[ "$mode" == "relocate" ]]; then
  require_command rsync
  require_command sha1sum

  if [[ -f "$state_file" ]]; then
    log_error "Existing relocation manifest found at $state_file"
    log_error "Run with --undo before relocating again to avoid conflicts."
    exit 1
  fi

  if (( dry_run == 0 )); then
    mkdir -p "$state_dir"
    rm -f "$state_dir"/items.* 2>/dev/null || true
  fi
fi

dir_empty() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  [[ -z $(ls -A "$dir" 2>/dev/null) ]]
}

ensure_symlink() {
  local src="$1" dst="$2"

  if [[ -L "$src" ]]; then
    local current_target
    current_target=$(readlink -f "$src" 2>/dev/null || true)
    local expected_target
    expected_target=$(readlink -f "$dst" 2>/dev/null || true)

    if [[ "$current_target" == "$expected_target" ]]; then
      log_debug "Already linked: $src -> $dst"
      return 0
    fi
    log_error "Refusing to relink $src (currently points to $current_target)"
    return 1
  fi

  if [[ -e "$src" ]]; then
    log_error "Refusing to overwrite non-symlink at $src"
    return 1
  fi

  if (( dry_run )); then
    log_info "[DRY-RUN] Would create symlink: $src -> $dst"
    return 0
  fi

  ln -s "$dst" "$src"
  log_info "Created symlink: $src -> $dst"
}

action_id() {
  printf '%s\n%s\n' "$1" "$2" | sha1sum | awk '{print $1}'
}

declare -a actions=()

write_item_manifest() {
  local manifest_id="$1"
  shift
  [[ -n "$manifest_id" ]] || return 0

  if (( dry_run )); then
    log_debug "[DRY-RUN] Would write manifest $manifest_id with $# items"
    return 0
  fi

  mkdir -p "$state_dir"
  local tmp
  tmp=$(mktemp -p "$state_dir" "items.$manifest_id.XXXXXX")
  tmp_item_files+=("$tmp")
  : > "$tmp"

  local entry
  for entry in "$@"; do
    printf '%s\n' "$entry" >> "$tmp"
  done

  # Verify file was written correctly
  if [[ ! -s "$tmp" ]]; then
    log_error "Failed to write manifest file"
    return 1
  fi

  mv "$tmp" "$state_dir/items.$manifest_id"
  log_debug "Wrote manifest: $state_dir/items.$manifest_id"
}

relocate_cache_dir() {
  local library="$1" subdir="$2"
  local src="$library/steamapps/$subdir"
  local dst="$steamapps_dir/$subdir"

  if [[ -L "$src" ]]; then
    log_debug "Skipping $src (already a symlink)"
    return 0
  fi

  if [[ ! -d "$src" ]]; then
    log_debug "Skipping $src (does not exist)"
    return 0
  fi

  # Create destination if it doesn't exist
  if (( dry_run == 0 )); then
    mkdir -p "$dst"
  fi

  # Find items to move
  mapfile -t items < <(find "$src" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | LC_ALL=C sort)

  if (( ${#items[@]} == 0 )); then
    if (( dry_run )); then
      log_info "[DRY-RUN] Would remove empty directory and create symlink: $src -> $dst"
    else
      rmdir "$src"
      ensure_symlink "$src" "$dst"
    fi
    actions+=("$library|$subdir|0|")
    return 0
  fi

  local src_size
  src_size=$(get_dir_size "$src")
  log_info "Processing $src (${#items[@]} items, $(human_readable_size "$src_size"))"

  # Check disk space if not skipped
  if (( skip_space_check == 0 && dry_run == 0 )); then
    if ! check_disk_space "$src" "$dst"; then
      log_error "Skipping $src due to insufficient disk space"
      return 1
    fi
  fi

  if (( dry_run )); then
    log_info "[DRY-RUN] Would move ${#items[@]} item(s) from $src to $dst"
    log_info "[DRY-RUN] Would create symlink: $src -> $dst"
    actions+=("$library|$subdir|1|dry-run-manifest")
    return 0
  fi

  # Perform the actual move with rsync
  local -a rsync_opts=(-a --remove-source-files)
  if (( show_progress )); then
    if [[ -t 1 ]]; then
      rsync_opts+=(--info=progress2 --human-readable)
    fi
  fi

  log_info "Moving cache data to main library..."
  if ! rsync "${rsync_opts[@]}" "$src"/ "$dst"/; then
    log_error "rsync failed while moving $src"
    return 1
  fi

  # Clean up empty directories
  find "$src" -depth -type d -empty -delete 2>/dev/null || true

  if ! dir_empty "$src"; then
    log_warn "$src still contains data; preserving directory"
    log_warn "Manual intervention may be required"
    return 0
  fi

  rmdir "$src" 2>/dev/null || {
    log_warn "Could not remove $src (directory not empty)"
    return 0
  }

  ensure_symlink "$src" "$dst" || return 1

  # Record action for undo
  local manifest=""
  if (( ${#items[@]} > 0 )); then
    manifest=$(action_id "$library" "$subdir")
    write_item_manifest "$manifest" "${items[@]}" || return 1
  fi
  actions+=("$library|$subdir|1|$manifest")
  log_info "Successfully relocated $src"
}

undo_cache_dir() {
  local library="$1" subdir="$2" moved="$3" manifest="$4"
  local src="$library/steamapps/$subdir"
  local dst="$steamapps_dir/$subdir"

  if [[ ! -L "$src" ]]; then
    log_warn "Skipping $src (not a symlink)"
    return 0
  fi

  local link_target
  link_target=$(readlink -f "$src" 2>/dev/null || true)
  if [[ "$link_target" != "$dst" ]]; then
    log_warn "Skipping $src (points to unexpected location: $link_target)"
    return 0
  fi

  if (( dry_run )); then
    log_info "[DRY-RUN] Would remove symlink: $src"
    log_info "[DRY-RUN] Would restore directory: $src"
    if [[ "$moved" == "1" && -n "$manifest" ]]; then
      log_info "[DRY-RUN] Would move cached items back from $dst"
    fi
    return 0
  fi

  rm "$src"
  mkdir -p "$src"
  log_info "Removed symlink and recreated directory: $src"

  if [[ "$moved" == "1" && -n "$manifest" ]]; then
    local manifest_file="$state_dir/items.$manifest"
    if [[ -f "$manifest_file" ]]; then
      local restored_count=0
      while IFS= read -r entry || [[ -n "$entry" ]]; do
        [[ -n "$entry" ]] || continue
        local src_entry="$src/$entry"
        local dst_entry="$dst/$entry"

        if [[ ! -e "$dst_entry" ]]; then
          log_warn "Cannot restore missing entry: $dst_entry"
          continue
        fi

        if [[ -e "$src_entry" ]]; then
          log_warn "Conflict restoring $entry; leaving in $dst"
          continue
        fi

        log_debug "Restoring: $entry"
        mv "$dst_entry" "$src" || {
          log_error "Failed to restore $entry"
          continue
        }
        restored_count=$((restored_count + 1))
      done < "$manifest_file"

      log_info "Restored $restored_count items to $src"
      rm -f "$manifest_file"
    else
      log_warn "Manifest $manifest_file not found; cache data remains in $dst"
    fi
  elif [[ "$moved" == "1" ]]; then
    log_warn "No manifest for $src; cache data remains in $dst"
  fi

  log_info "Completed restoration of $src"
}

# Main execution: UNDO mode
if [[ "$mode" == "undo" ]]; then
  if [[ ! -f "$state_file" ]]; then
    log_info "No relocation state found; nothing to undo."
    exit 0
  fi

  log_info "Beginning undo operation..."
  undo_count=0

  while IFS=$'\t' read -r library subdir moved manifest; do
    [[ -n "$library" && -n "$subdir" ]] || continue
    undo_cache_dir "$library" "$subdir" "$moved" "${manifest:-}"
    undo_count=$((undo_count + 1))
  done < "$state_file"

  if (( dry_run )); then
    log_info "[DRY-RUN] Would remove state file: $state_file"
  else
    rm -f "$state_file"
    rm -f "$state_dir"/items.* 2>/dev/null || true
    rmdir "$state_dir" 2>/dev/null || true
  fi

  log_info "Undo complete ($undo_count operations processed)"
  exit 0
fi

# Main execution: RELOCATE mode
log_info "Beginning cache relocation..."
relocated_count=0
failed_count=0

for library in "${library_paths[@]}"; do
  if [[ "$library" == "$main_dir" ]]; then
    log_debug "Skipping main library: $library"
    continue
  fi

  log_info "Processing library: $library"

  for sub in "${CACHE_TARGETS[@]}"; do
    if relocate_cache_dir "$library" "$sub"; then
      relocated_count=$((relocated_count + 1))
    else
      failed_count=$((failed_count + 1))
      log_error "Failed to relocate $library/steamapps/$sub"
    fi
  done
done

# Write state file
if [[ ${#actions[@]} -gt 0 ]]; then
  if (( dry_run )); then
    log_info "[DRY-RUN] Would write state file with ${#actions[@]} entries"
  else
    mkdir -p "$state_dir"
    tmp_state_file=$(mktemp -p "$state_dir" state.XXXXXX)
    : > "$tmp_state_file"

    for entry in "${actions[@]}"; do
      IFS='|' read -r library subdir moved manifest <<< "$entry"
      printf '%s\t%s\t%s\t%s\n' "$library" "$subdir" "$moved" "$manifest" >> "$tmp_state_file"
    done

    # Verify state file was written correctly
    if [[ ! -s "$tmp_state_file" ]]; then
      log_error "Failed to write state file"
      exit 1
    fi

    mv "$tmp_state_file" "$state_file"
    tmp_state_file=""
    log_info "State file written: $state_file"
  fi
else
  log_info "No changes made"
  if (( dry_run == 0 )); then
    rm -f "$state_file" 2>/dev/null || true
    rm -f "$state_dir"/items.* 2>/dev/null || true
    rmdir "$state_dir" 2>/dev/null || true
  fi
fi

# Final summary
log_info "===================================="
if (( dry_run )); then
  log_info "DRY RUN COMPLETE - No changes made"
else
  log_info "RELOCATION COMPLETE"
fi
log_info "Processed: $relocated_count operations"
if (( failed_count > 0 )); then
  log_warn "Failed: $failed_count operations"
fi
log_info "Target directory: $steamapps_dir"
log_info "===================================="

if (( failed_count > 0 )); then
  exit 1
fi

exit 0
