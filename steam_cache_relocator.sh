#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '%s\n' "$*" >&2
}

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--undo] [main_steam_dir]

Relocate or restore shader and Proton caches between secondary Steam
libraries and the primary Steam directory (default: $HOME/.local/share/Steam).

Options:
  --undo        Restore directories that were previously symlinked by this script.
  --no-progress  Disable rsync progress output.
  -h, --help    Show this help message.
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Required command '$1' not found. Install it and retry."
    exit 1
  fi
}

mode="relocate"
show_progress=1
declare -a positional=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --undo)
      mode="undo"
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
      log "Unknown option: $1"
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
  log "Too many arguments"
  usage
  exit 1
fi

main_dir="${positional[0]:-$HOME/.local/share/Steam}"
if [[ ! -d "$main_dir" ]]; then
  alt="$HOME/.steam/steam"
  if [[ -d "$alt" ]]; then
    log "Fallback to $alt"
    main_dir="$alt"
  else
    log "Steam directory not found. Pass it explicitly."
    exit 1
  fi
fi

main_dir=$(readlink -f "$main_dir")
steamapps_dir="$main_dir/steamapps"
if [[ ! -d "$steamapps_dir" ]]; then
  log "Missing steamapps directory under $main_dir"
  exit 1
fi

state_dir="$steamapps_dir/.steam_cache_relocator"
state_file="$state_dir/state.tsv"

tmp_state_file=""
declare -a tmp_item_files=()
cleanup_tmp_artifacts() {
  [[ -n "$tmp_state_file" && -f "$tmp_state_file" ]] && rm -f "$tmp_state_file"
  for tmp in "${tmp_item_files[@]}"; do
    [[ -f "$tmp" ]] && rm -f "$tmp"
  done
}
trap cleanup_tmp_artifacts EXIT

library_file="$steamapps_dir/libraryfolders.vdf"
if [[ ! -f "$library_file" ]]; then
  log "Cannot locate $library_file"
  exit 1
fi

mapfile -t raw_paths < <(awk -F'"' '/"path"/ {print $4}' "$library_file")
raw_paths+=("$main_dir")

declare -A seen=()
library_paths=()
for path in "${raw_paths[@]}"; do
  [[ -n "$path" ]] || continue
  resolved=$(readlink -f "$path" 2>/dev/null || printf '%s' "$path")
  if [[ ! -d "$resolved" ]]; then
    log "Skipping missing library $resolved"
    continue
  fi
  if [[ -z ${seen[$resolved]+x} ]]; then
    seen[$resolved]=1
    library_paths+=("$resolved")
  fi
done

if [[ ${#library_paths[@]} -le 1 ]]; then
  log "No secondary Steam libraries detected."
  if [[ "$mode" == "undo" ]]; then
    log "Undo skipped."
  fi
  exit 0
fi

CACHE_TARGETS=(shadercache steamshadercache compatdata)

if [[ "$mode" == "relocate" ]]; then
  require_command rsync
  require_command sha1sum
  if [[ -f "$state_file" ]]; then
    log "Existing relocation manifest found at $state_file. Run with --undo before relocating again."
    exit 1
  fi
  mkdir -p "$state_dir"
  rm -f "$state_dir"/items.* 2>/dev/null || true
fi

dir_empty() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  [[ -z $(ls -A "$dir") ]]
}

ensure_symlink() {
  local src="$1" dst="$2"
  if [[ -L "$src" ]]; then
    if [[ $(readlink -f "$src" 2>/dev/null || true) == $(readlink -f "$dst" 2>/dev/null || true) ]]; then
      log "Already linked: $src"
      return 0
    fi
    log "Refusing to relink because $src points elsewhere"
    return 1
  fi
  if [[ -e "$src" ]]; then
    log "Refusing to overwrite non-symlink at $src"
    return 1
  fi
  ln -s "$dst" "$src"
  log "Linked $src -> $dst"
}

action_id() {
  printf '%s\n%s\n' "$1" "$2" | sha1sum | awk '{print $1}'
}

declare -a actions=()

write_item_manifest() {
  local manifest_id="$1"
  shift
  [[ -n "$manifest_id" ]] || return 0
  mkdir -p "$state_dir"
  local tmp
  tmp=$(mktemp -p "$state_dir" "items.$manifest_id.XXXXXX")
  tmp_item_files+=("$tmp")
  : > "$tmp"
  local entry
  for entry in "$@"; do
    printf '%s\n' "$entry" >> "$tmp"
  done
  mv "$tmp" "$state_dir/items.$manifest_id"
}

relocate_cache_dir() {
  local library="$1" subdir="$2"
  local src="$library/steamapps/$subdir"
  local dst="$steamapps_dir/$subdir"

  if [[ -L "$src" ]]; then
    log "Skipping $src (already symlink)"
    return 0
  fi
  if [[ ! -d "$src" ]]; then
    return 0
  fi

  mkdir -p "$dst"

  mapfile -t items < <(find "$src" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | LC_ALL=C sort)
  if (( ${#items[@]} == 0 )); then
    rmdir "$src"
    ensure_symlink "$src" "$dst"
    actions+=("$library|$subdir|0|")
    return 0
  fi

  log "Moving ${#items[@]} item(s) from $src to $dst"
  local -a rsync_opts=(-a --remove-source-files)
  if (( show_progress )); then
    if [[ -t 1 ]]; then
      rsync_opts+=(--info=progress2 --human-readable)
    fi
  fi
  if ! rsync "${rsync_opts[@]}" "$src"/ "$dst"/; then
    log "rsync failed while moving $src"
    return 1
  fi
  find "$src" -depth -type d -empty -delete || true

  if ! dir_empty "$src"; then
    log "Warning: $src still contains data; leaving remainder in place"
  fi

  rmdir "$src" 2>/dev/null || true
  ensure_symlink "$src" "$dst"

  local manifest=""
  if (( ${#items[@]} > 0 )); then
    manifest=$(action_id "$library" "$subdir")
    write_item_manifest "$manifest" "${items[@]}"
  fi
  actions+=("$library|$subdir|1|$manifest")
}

undo_cache_dir() {
  local library="$1" subdir="$2" moved="$3" manifest="$4"
  local src="$library/steamapps/$subdir"
  local dst="$steamapps_dir/$subdir"

  if [[ ! -L "$src" ]]; then
    log "Skipping $src (not a symlink)"
    return 0
  fi

  local link_target
  link_target=$(readlink -f "$src" 2>/dev/null || true)
  if [[ "$link_target" != "$dst" ]]; then
    log "Skipping $src (points to $link_target)"
    return 0
  fi

  rm "$src"
  mkdir -p "$src"

  if [[ "$moved" == "1" && -n "$manifest" ]]; then
    local manifest_file="$state_dir/items.$manifest"
    if [[ -f "$manifest_file" ]]; then
      while IFS= read -r entry || [[ -n "$entry" ]]; do
        [[ -n "$entry" ]] || continue
        local src_entry="$src/$entry"
        local dst_entry="$dst/$entry"
        if [[ ! -e "$dst_entry" ]]; then
          log "Skipping missing entry $dst_entry"
          continue
        fi
        if [[ -e "$src_entry" ]]; then
          log "Conflict restoring $src_entry; leaving data in $dst_entry"
          continue
        fi
        log "Restoring $dst_entry -> $src"
        mv "$dst_entry" "$src"
      done < "$manifest_file"
      rm -f "$manifest_file"
    else
      log "Manifest $manifest_file missing; cache stays in $dst"
    fi
  elif [[ "$moved" == "1" ]]; then
    log "No manifest recorded for $src; cache data remains in $dst"
  fi

  log "Restored directory $src"
}

if [[ "$mode" == "undo" ]]; then
  if [[ ! -f "$state_file" ]]; then
    log "No relocation state found; nothing to undo."
    exit 0
  fi
  while IFS=$'\t' read -r library subdir moved manifest; do
    [[ -n "$library" && -n "$subdir" ]] || continue
    undo_cache_dir "$library" "$subdir" "$moved" "${manifest:-}"
  done < "$state_file"
  rm -f "$state_file"
  rm -f "$state_dir"/items.* 2>/dev/null || true
  rmdir "$state_dir" 2>/dev/null || true
  log "Undo complete."
  exit 0
fi

for library in "${library_paths[@]}"; do
  if [[ "$library" == "$main_dir" ]]; then
    continue
  fi
  for sub in "${CACHE_TARGETS[@]}"; do
    relocate_cache_dir "$library" "$sub"
  done
done

if [[ ${#actions[@]} -gt 0 ]]; then
  mkdir -p "$state_dir"
  tmp_state_file=$(mktemp -p "$state_dir" state.XXXXXX)
  : > "$tmp_state_file"
  for entry in "${actions[@]}"; do
    IFS='|' read -r library subdir moved manifest <<< "$entry"
    printf '%s\t%s\t%s\t%s\n' "$library" "$subdir" "$moved" "$manifest" >> "$tmp_state_file"
  done
  mv "$tmp_state_file" "$state_file"
  tmp_state_file=""
else
  rm -f "$state_file" 2>/dev/null || true
  rm -f "$state_dir"/items.* 2>/dev/null || true
  rmdir "$state_dir" 2>/dev/null || true
fi

log "Done. Future shader and Proton caches now land on $steamapps_dir"
