#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '%s\n' "$*" >&2
}

usage() {
  cat <<'USAGE'
Usage: $(basename "$0") [options]

Install or remove a fontconfig snippet that prioritises Noto families for
sans-serif, serif, and monospace fallbacks with Thai coverage.

Options:
  --install        Install or update the configuration (default)
  --remove         Remove the configuration
  --status         Report whether the configuration is active
  --system         Target the system-wide fontconfig directories (default)
  --user           Target the per-user fontconfig directories (~/.config/fontconfig)
  --dry-run        Print intended actions without modifying anything
  --no-cache       Skip running fc-cache after changes
  --force          Overwrite conflicting files instead of aborting
  --no-font-install  Skip checking/auto-installing Noto font packages
  --flatpak        Apply Flatpak override so sandboxed apps see this config (user scope)
  -h, --help       Show this help message
USAGE
}

CONFIG_NAME="60-noto-prefer-thai.conf"

REQUIRED_FONTS=("Noto Sans" "Noto Sans Thai" "Noto Sans Mono" "Noto Serif" "Noto Serif Thai" "Noto Color Emoji")

config_payload() {
  cat <<'XML'
<?xml version='1.0'?>
<!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
<fontconfig>
 <!-- Prefer Noto for generic families (minimal set) -->
 <alias>
  <family>sans-serif</family>
  <prefer>
   <family>Noto Sans</family>
   <family>Noto Sans Thai</family>
   <!-- non-looped -->
   <family>Noto Color Emoji</family>
  </prefer>
 </alias>
 <alias>
  <family>serif</family>
  <prefer>
   <family>Noto Serif</family>
   <family>Noto Serif Thai</family>
   <family>Noto Color Emoji</family>
  </prefer>
 </alias>
 <alias>
  <family>monospace</family>
  <prefer>
   <family>Noto Sans Mono</family>
   <family>Noto Sans Thai</family>
   <family>Noto Color Emoji</family>
  </prefer>
 </alias>
 <!-- Strong bindings so generic families favour Noto first -->
 <match target="pattern">
  <test name="family" qual="any">
   <string>serif</string>
  </test>
  <edit binding="strong" mode="prepend" name="family">
   <string>Noto Serif</string>
   <string>Noto Serif Thai</string>
  </edit>
 </match>
 <match target="pattern">
  <test name="family" qual="any">
   <string>sans-serif</string>
  </test>
  <edit binding="strong" mode="prepend" name="family">
   <string>Noto Sans</string>
   <string>Noto Sans Thai</string>
   <!-- non-looped -->
  </edit>
 </match>
 <!-- Monospace contexts: make sure Noto covers codepoints -->
 <match target="pattern">
  <test name="family" qual="any">
   <string>monospace</string>
  </test>
  <edit binding="strong" mode="prepend" name="family">
   <string>Noto Sans Mono</string>
   <string>Noto Sans Thai</string>
  </edit>
 </match>
 <dir>~/.local/share/fonts</dir>
</fontconfig>
XML
}

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    log "This operation requires root. Re-run with sudo or as root."
    exit 1
  fi
}

maybe_backup() {
  local path="$1"
  local dry_run_flag=$2
  local force_flag=$3

  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 0
  fi

  if [[ $force_flag -eq 1 ]]; then
    log "Overwriting $path (forced, no backup)."
    return 0
  fi

  local backup="${path}.bak.$(date +%Y%m%d%H%M%S)"
  log "Backing up $path to $backup"
  if [[ $dry_run_flag -eq 0 ]]; then
    mv "$path" "$backup"
  fi
}

write_config() {
  local dest="$1"
  local dry_run_flag=$2
  local force_flag=$3

  if [[ -f "$dest" ]]; then
    if diff -q <(config_payload) "$dest" >/dev/null 2>&1; then
      log "Configuration already up to date at $dest"
      return 0
    fi
    maybe_backup "$dest" "$dry_run_flag" "$force_flag"
  else
    if [[ $dry_run_flag -eq 1 ]]; then
      log "Dry run: would create $dest"
    else
      log "Creating $dest"
    fi
  fi

  if [[ $dry_run_flag -eq 0 ]]; then
    local tmp
    tmp=$(mktemp)
    config_payload > "$tmp"
    install -m 0644 "$tmp" "$dest"
    rm -f "$tmp"
  fi
}

ensure_symlink() {
  local link_path="$1"
  local target_path="$2"
  local dry_run_flag=$3
  local force_flag=$4

  if [[ -L "$link_path" ]]; then
    local resolved
    resolved=$(readlink -f "$link_path" 2>/dev/null || true)
    local canonical
    canonical=$(readlink -f "$target_path" 2>/dev/null || true)
    if [[ "$resolved" == "$canonical" ]]; then
      log "Symlink already present at $link_path"
      return 0
    fi
    if [[ $force_flag -eq 0 ]]; then
      log "Refusing to replace existing symlink $link_path (use --force)."
      exit 1
    fi
    log "Replacing conflicting symlink $link_path"
    if [[ $dry_run_flag -eq 0 ]]; then
      rm -f "$link_path"
    fi
  elif [[ -e "$link_path" ]]; then
    if [[ -d "$link_path" ]]; then
      log "$link_path is a directory; refusing to replace"
      exit 1
    fi
    if [[ $force_flag -eq 0 ]]; then
      log "Existing file at $link_path (use --force to replace)."
      exit 1
    fi
    maybe_backup "$link_path" "$dry_run_flag" "$force_flag"
    if [[ $dry_run_flag -eq 0 ]]; then
      rm -f "$link_path"
    fi
  fi

  if [[ $dry_run_flag -eq 1 ]]; then
    log "Dry run: would link $link_path -> $target_path"
  else
    log "Linking $link_path -> $target_path"
    ln -s "$target_path" "$link_path"
  fi
}

is_config_active() {
  local link_path="$1"
  local target_path="$2"

  [[ -L "$link_path" ]] || return 1
  local resolved
  resolved=$(readlink -f "$link_path" 2>/dev/null || true)
  local canonical
  canonical=$(readlink -f "$target_path" 2>/dev/null || true)
  [[ "$resolved" == "$canonical" ]]
}

remove_config() {
  local avail_path="$1"
  local link_path="$2"
  local dry_run_flag=$3

  if is_config_active "$link_path" "$avail_path"; then
    if [[ $dry_run_flag -eq 1 ]]; then
      log "Dry run: would remove symlink $link_path"
    else
      log "Removing symlink $link_path"
      rm -f "$link_path"
    fi
  elif [[ -L "$link_path" ]]; then
    log "Skipping $link_path (points elsewhere)"
  fi

  if [[ -f "$avail_path" ]]; then
    if diff -q <(config_payload) "$avail_path" >/dev/null 2>&1; then
      if [[ $dry_run_flag -eq 1 ]]; then
        log "Dry run: would remove $avail_path"
      else
        log "Removing $avail_path"
        rm -f "$avail_path"
      fi
    else
      log "Skipping $avail_path (contents differ)"
    fi
  fi
}

refresh_cache() {
  local dry_run_flag=$1

  if [[ $dry_run_flag -eq 1 ]]; then
    log "Dry run: skipping fc-cache"
    return
  fi

  if command -v fc-cache >/dev/null 2>&1; then
    log "Refreshing font cache"
    if ! fc-cache -f >/dev/null 2>&1; then
      log "Warning: fc-cache returned a non-zero status"
    fi
  else
    log "fc-cache not found; skipping cache refresh"
  fi
}

font_installed() {
  local face="$1"
  if ! command -v fc-list >/dev/null 2>&1; then
    if [[ ${FC_LIST_WARNED:-0} -eq 0 ]]; then
      log "fc-list not found; unable to verify installed fonts"
      FC_LIST_WARNED=1
    fi
    return 1
  fi
  local count
  count=$(fc-list "$face" 2>/dev/null | wc -l | tr -d ' \n')
  [[ "${count:-0}" -gt 0 ]]
}

detect_package_manager() {
  if command -v pacman >/dev/null 2>&1; then
    printf 'pacman'
  elif command -v paru >/dev/null 2>&1; then
    printf 'pacman'
  elif command -v yay >/dev/null 2>&1; then
    printf 'pacman'
  elif command -v apt-get >/dev/null 2>&1; then
    printf 'apt'
  elif command -v apt >/dev/null 2>&1; then
    printf 'apt'
  elif command -v dnf >/dev/null 2>&1; then
    printf 'dnf'
  elif command -v yum >/dev/null 2>&1; then
    printf 'dnf'
  elif command -v zypper >/dev/null 2>&1; then
    printf 'zypper'
  elif command -v emerge >/dev/null 2>&1; then
    printf 'emerge'
  else
    printf 'unknown'
  fi
}

install_fonts_if_needed() {
  local target_scope="$1"
  local dry_run_flag=$2
  local skip_install=$3

  local missing=()
  for face in "${REQUIRED_FONTS[@]}"; do
    if ! font_installed "$face"; then
      missing+=("$face")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  log "Detected missing fonts: ${missing[*]}"

  if [[ $skip_install -eq 1 ]]; then
    log "Font installation skipped due to --no-font-install"
    return 0
  fi

  if [[ $dry_run_flag -eq 1 ]]; then
    log "Dry run: would attempt to install required fonts"
    return 0
  fi

  local mgr
  mgr=$(detect_package_manager)

  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    log "Fonts missing but not running as root; install the packages manually or re-run with sudo."
    return 0
  fi

  case "$mgr" in
    pacman)
      local pkg_list=("noto-fonts" "noto-fonts-cjk" "noto-fonts-extra")
      log "Using pacman to install: ${pkg_list[*]}"
      pacman -S --needed --noconfirm "${pkg_list[@]}"
      ;;
    apt)
      local pkg_list=("fonts-noto-core" "fonts-noto-color-emoji" "fonts-noto-unhinted")
      log "Using apt to install: ${pkg_list[*]}"
      apt-get update
      apt-get install -y "${pkg_list[@]}"
      ;;
    dnf)
      local pkg_list=("google-noto-sans-fonts" "google-noto-serif-fonts" "google-noto-sans-thai-fonts" "google-noto-emoji-color-fonts" "google-noto-mono-fonts")
      log "Using dnf to install: ${pkg_list[*]}"
      dnf install -y "${pkg_list[@]}"
      ;;
    zypper)
      local pkg_list=("google-noto-sans-fonts" "google-noto-serif-fonts" "google-noto-sans-thai-fonts" "google-noto-emoji-color-fonts" "google-noto-mono-fonts")
      log "Using zypper to install: ${pkg_list[*]}"
      zypper --non-interactive install --auto-agree-with-licenses "${pkg_list[@]}"
      ;;
    emerge)
      local pkg_list=("media-fonts/noto" "media-fonts/noto-emoji")
      log "Using emerge to install: ${pkg_list[*]}"
      emerge --ask=n --quiet "${pkg_list[@]}"
      ;;
    *)
      log "Package manager not detected; install the missing fonts manually."
      return 0
      ;;
  esac
}

apply_flatpak_override() {
  local dry_run_flag=$1
  local target_scope=$2

  if [[ $target_scope != "user" ]]; then
    log "--flatpak is only supported with --user installs; skipping"
    return
  fi

  local override_cmd=(flatpak override --user --filesystem=xdg-config/fontconfig:ro --filesystem=xdg-data/fonts:ro)

  if [[ $dry_run_flag -eq 1 ]]; then
    log "Dry run: would run ${override_cmd[*]}"
    return
  fi

  if ! command -v flatpak >/dev/null 2>&1; then
    log "flatpak command not found; skipping Flatpak override"
    return
  fi

  if "${override_cmd[@]}" >/dev/null 2>&1; then
    log "Applied Flatpak override to expose host fontconfig and fonts"
  else
    log "Warning: failed to apply Flatpak override"
  fi
}

mode="install"
target="system"
dry_run=0
refresh=1
force=0
skip_font_install=0
configure_flatpak=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      mode="install"
      shift
      ;;
    --remove)
      mode="remove"
      shift
      ;;
    --status)
      mode="status"
      shift
      ;;
    --system)
      target="system"
      shift
      ;;
    --user)
      target="user"
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --no-cache)
      refresh=0
      shift
      ;;
    --force)
      force=1
      shift
      ;;
    --no-font-install)
      skip_font_install=1
      shift
      ;;
    --flatpak)
      configure_flatpak=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      ;;
    -*)
      log "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      log "Unexpected argument: $1"
      usage
      exit 1
      ;;
  esac
done

base_dir=""
avail_dir=""
conf_dir=""

case "$target" in
  system)
    base_dir="/etc/fonts"
    avail_dir="$base_dir/conf.avail"
    conf_dir="$base_dir/conf.d"
    ;;
  user)
    base_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig"
    avail_dir="$base_dir/conf.avail"
    conf_dir="$base_dir/conf.d"
    ;;
  *)
    log "Unknown target $target"
    exit 1
    ;;
esac

avail_path="$avail_dir/$CONFIG_NAME"
link_path="$conf_dir/$CONFIG_NAME"

if [[ "$mode" != "status" ]]; then
  if [[ $target == "system" ]]; then
    require_root
  fi

  log "Target: $target"
  log "Configuration path: $avail_path"
fi

case "$mode" in
  install)
    if [[ $dry_run -eq 0 ]]; then
      mkdir -p "$avail_dir" "$conf_dir"
    else
      log "Dry run: would ensure directories $avail_dir and $conf_dir"
    fi
    install_fonts_if_needed "$target" "$dry_run" "$skip_font_install"
    write_config "$avail_path" "$dry_run" "$force"
    ensure_symlink "$link_path" "$avail_path" "$dry_run" "$force"
    if [[ $refresh -eq 1 ]]; then
      refresh_cache "$dry_run"
    else
    log "Skipping fc-cache refresh per --no-cache"
    fi
    if [[ $configure_flatpak -eq 1 ]]; then
      apply_flatpak_override "$dry_run" "$target"
    fi
    ;;
  remove)
    remove_config "$avail_path" "$link_path" "$dry_run"
    if [[ $refresh -eq 1 ]]; then
      refresh_cache "$dry_run"
    else
      log "Skipping fc-cache refresh per --no-cache"
    fi
    ;;
  status)
    if [[ -f "$avail_path" ]] && diff -q <(config_payload) "$avail_path" >/dev/null 2>&1; then
      log "Config file present at $avail_path"
    elif [[ -f "$avail_path" ]]; then
      log "Different file present at $avail_path"
    else
      log "Config file not found at $avail_path"
    fi

    if is_config_active "$link_path" "$avail_path"; then
      log "Symlink active at $link_path"
    elif [[ -L "$link_path" ]]; then
      log "Symlink at $link_path points elsewhere"
    elif [[ -e "$link_path" ]]; then
      log "Non-symlink entry present at $link_path"
    else
      log "No entry at $link_path"
    fi
    ;;
  *)
    log "Unsupported mode $mode"
    exit 1
    ;;
esac
