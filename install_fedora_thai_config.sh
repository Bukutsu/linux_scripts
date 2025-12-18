#!/usr/bin/env bash
#
# Fedora Thai Font Configuration Installer
#
# Installs Fedora's official font configuration logic for Thai language support
# into the user's home directory. This allows any Linux distribution (Ubuntu, Arch, etc.)
# to render Thai text as correctly and beautifully as Fedora does.
#
# Features:
# - Installs specific Fontconfig rules to prioritize "Noto Sans Thai" and "Noto Serif Thai".
# - Configures Flatpak applications to respect these settings.
# - Safe to run on any distro (does not touch system files).
#

set -euo pipefail
export LC_ALL=C

# ============================================================================ 
# CONSTANTS
# ============================================================================ 

readonly SCRIPT_NAME="$(basename "$0")"
readonly CONFIG_FILENAME="99-fedora-thai-rules.conf"
readonly USER_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig"
readonly USER_CONF_D="${USER_CONF_DIR}/conf.d"

# ============================================================================ 
# LOGGING
# ============================================================================ 

log() { printf "[INFO] %s\n" "$*"; }
error() { printf "[ERROR] %s\n" "$*" >&2; }
die() { error "$1"; exit "${2:-1}"; }

# ============================================================================ 
# FEDORA CONFIGURATION PAYLOAD
# ============================================================================ 
# This XML is based on Fedora 43's official configuration:
# - /etc/fonts/conf.d/65-0-google-noto-sans-thai-vf.conf
# - /etc/fonts/conf.d/65-0-google-noto-serif-thai-vf.conf

get_fedora_config_payload() {
  cat <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <!-- Fedora Logic: Prepend Noto Sans Thai for Sans-Serif when language is Thai -->
  <match>
    <test name="lang" compare="contains">
      <string>th</string>
    </test>
    <test name="family">
      <string>sans-serif</string>
    </test>
    <edit name="family" mode="prepend">
      <string>Noto Sans Thai</string>
    </edit>
  </match>

  <!-- Fedora Logic: Prepend Noto Serif Thai for Serif when language is Thai -->
  <match>
    <test name="lang" compare="contains">
      <string>th</string>
    </test>
    <test name="family">
      <string>serif</string>
    </test>
    <edit name="family" mode="prepend">
      <string>Noto Serif Thai</string>
    </edit>
  </match>

  <!-- Fedora Logic: Monospace fallback -->
  <match>
    <test name="lang" compare="contains">
      <string>th</string>
    </test>
    <test name="family">
      <string>monospace</string>
    </test>
    <edit name="family" mode="prepend">
      <string>Noto Sans Thai</string>
    </edit>
  </match>

  <!-- Aliases for fallback -->
  <alias>
    <family>Noto Sans Thai</family>
    <default>
      <family>sans-serif</family>
    </default>
  </alias>
  <alias>
    <family>Noto Serif Thai</family>
    <default>
      <family>serif</family>
    </default>
  </alias>
</fontconfig>
EOF
}

# ============================================================================ 
# MAIN LOGIC
# ============================================================================ 

main() {
  local dry_run=0
  local skip_flatpak=0

  # Simple argument parsing
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=1 ;; 
      --no-flatpak) skip_flatpak=1 ;; 
      -h|--help)
        echo "Usage: $SCRIPT_NAME [--dry-run] [--no-flatpak]"
        exit 0
        ;; 
      *) die "Unknown argument: $1" ;; 
    esac
    shift
  done

  log "Starting Fedora Thai Font Configuration Installer..."

  # 1. Ensure Directory Structure
  if [[ $dry_run -eq 1 ]]; then
    log "[Dry Run] Would create directory: $USER_CONF_D"
  else
    mkdir -p "$USER_CONF_D"
  fi

  # 2. Write the Configuration File
  local target_file="$USER_CONF_D/$CONFIG_FILENAME"
  if [[ $dry_run -eq 1 ]]; then
    log "[Dry Run] Would write Fedora configuration to: $target_file"
  else
    log "Writing configuration to $target_file..."
    get_fedora_config_payload > "$target_file"
  fi

  # 3. Ensure fonts.conf includes conf.d
  # Many systems already do this, but if fonts.conf is missing or empty, we create a basic one.
  local main_conf="$USER_CONF_DIR/fonts.conf"
  if [[ ! -f "$main_conf" ]]; then
    if [[ $dry_run -eq 1 ]]; then
      log "[Dry Run] Would create basic fonts.conf at $main_conf"
    else
      log "Creating basic fonts.conf..."
      cat > "$main_conf" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <include ignore_missing="yes">conf.d</include>
</fontconfig>
EOF
    fi
  fi

  # 4. Refresh Font Cache
  if command -v fc-cache >/dev/null 2>&1; then
    if [[ $dry_run -eq 1 ]]; then
      log "[Dry Run] Would run: fc-cache -f --user"
    else
      log "Refreshing font cache..."
      fc-cache -f --user || log "[WARN] fc-cache failed, changes might not take effect immediately."
    fi
  else
    log "[WARN] fc-cache not found. You may need to restart applications manually."
  fi

  # 5. Configure Flatpak
  if [[ $skip_flatpak -eq 0 ]] && command -v flatpak >/dev/null 2>&1; then
    log "Configuring Flatpak..."
    
    # We expose the user's config directory to Flatpak
    if [[ $dry_run -eq 1 ]]; then
      log "[Dry Run] Would run: flatpak override --user --filesystem=xdg-config/fontconfig:ro"
    else
      flatpak override --user --filesystem=xdg-config/fontconfig:ro
      log "Flatpak override applied."
    fi
  fi

  log "Done! Your Thai fonts should now render using Fedora's rules."
}

main "$@"
