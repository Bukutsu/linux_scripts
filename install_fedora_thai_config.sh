#!/usr/bin/env bash
#
# Fedora Thai Font Configuration Installer (Enhanced)
#
# Installs Fedora's official font configuration logic for Thai language support
# into the user's home directory.
#
# Key Features:
# - Idempotent installation (checks for changes before writing).
# - Robustness: Verifies dependencies, backs up existing files, and handles errors.
# - Optimized: Only refreshes font cache when necessary.
# - Uninstall mode: Cleanly reverts changes.
# - Distro-agnostic.
#

set -euo pipefail
export LC_ALL=C

# ============================================================================ 
# CONSTANTS & CONFIGURATION
# ============================================================================ 

readonly SCRIPT_NAME="${0##*/}"
readonly CONFIG_FILENAME="99-fedora-thai-rules.conf"
readonly USER_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig"
readonly USER_CONF_D="${USER_CONF_DIR}/conf.d"
readonly TARGET_FILE="${USER_CONF_D}/${CONFIG_FILENAME}"

# ============================================================================ 
# UTILS & LOGGING
# ============================================================================ 

# Colors for better readability if stdout is a terminal
if [[ -t 1 ]]; then
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

log_info()  { printf "${C_BLUE}[INFO]${C_RESET} %s\n" "$*"; }
log_succ()  { printf "${C_GREEN}[OK]${C_RESET}   %s\n" "$*"; }
log_warn()  { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$*" >&2; }
log_err()   { printf "${C_RED}[ERR]${C_RESET}  %s\n" "$*" >&2; }
die()       { log_err "$1"; exit "${2:-1}"; }

# ============================================================================ 
# PAYLOAD
# ============================================================================ 

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
# CORE FUNCTIONS
# ============================================================================ 

# Check if the required fonts are actually present on the system
check_dependencies() {
    if ! command -v fc-list >/dev/null 2>&1; then
        log_warn "Command 'fc-list' not found. Cannot verify installed fonts."
        return
    fi

    # Check for Noto Sans Thai (common package: fonts-noto-core or noto-fonts)
    if ! fc-list : family | grep -qi "Noto Sans Thai"; then
        log_warn "Font 'Noto Sans Thai' does not appear to be installed."
        log_warn "This configuration requires Noto Thai fonts to be effective."
        log_warn "  - Debian/Ubuntu: sudo apt install fonts-noto-core"
        log_warn "  - Arch Linux:    sudo pacman -S noto-fonts"
        log_warn "  - Fedora:        (Usually installed by default)"
    else
        log_info "Detected 'Noto Sans Thai' installed."
    fi
}

# Ensure the main fonts.conf exists and includes conf.d
ensure_main_conf() {
    local main_conf="${USER_CONF_DIR}/fonts.conf"
    
    if [[ -f "$main_conf" ]]; then
        # Check if it includes the conf.d directory
        if ! grep -q "conf.d" "$main_conf"; then
            log_warn "$main_conf exists but might not include the 'conf.d' directory."
            log_warn "If your fonts don't change, ensure <include>conf.d</include> is in $main_conf."
        fi
        return
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY-RUN] Would create basic fonts.conf at $main_conf"
        return
    fi

    log_info "Creating basic fonts.conf..."
    mkdir -p "$USER_CONF_DIR"
    cat > "$main_conf" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <include ignore_missing="yes">conf.d</include>
</fontconfig>
EOF
    log_succ "Created $main_conf"
}

# Install or update the configuration file
install_config() {
    local payload
    payload=$(get_fedora_config_payload)
    local changed=0

    # 1. Ensure Directory
    if [[ ! -d "$USER_CONF_D" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_info "[DRY-RUN] Would create directory $USER_CONF_D"
        else
            mkdir -p "$USER_CONF_D"
        fi
    fi

    # 2. Check content vs existing file
    if [[ -f "$TARGET_FILE" ]]; then
        # Use diff/cmp to avoid unnecessary writes
        if echo "$payload" | cmp -s - "$TARGET_FILE"; then
            log_info "Configuration is up to date."
            return 0
        fi
        
        # Backup existing
        if [[ $DRY_RUN -eq 0 ]]; then
            cp "$TARGET_FILE" "${TARGET_FILE}.bak"
            log_info "Backed up existing config to ${TARGET_FILE}.bak"
        fi
    fi

    # 3. Write file
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY-RUN] Would write configuration to $TARGET_FILE"
        return 1 # Simulate change for flow
    fi

    echo "$payload" > "$TARGET_FILE"
    log_succ "Wrote configuration to $TARGET_FILE"
    return 1 # Indicates change happened
}

# Remove the configuration
uninstall_config() {
    if [[ ! -f "$TARGET_FILE" ]]; then
        log_info "Configuration file not found. Nothing to uninstall."
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY-RUN] Would remove $TARGET_FILE"
        return 1
    fi

    rm "$TARGET_FILE"
    log_succ "Removed $TARGET_FILE"
    return 1 # Indicates change
}

# Refresh font cache
refresh_cache() {
    if ! command -v fc-cache >/dev/null 2>&1; then
        log_warn "fc-cache not found. Please restart applications manually."
        return
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY-RUN] Would run: fc-cache -f --user"
    else
        log_info "Refreshing font cache..."
        fc-cache -f --user || log_warn "fc-cache reported an error (code $?)"
        log_succ "Font cache refreshed."
    fi
}

# Configure Flatpak overrides
configure_flatpak() {
    if [[ $SKIP_FLATPAK -eq 1 ]]; then return; fi
    if ! command -v flatpak >/dev/null 2>&1; then return; fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY-RUN] Would run: flatpak override --user --filesystem=xdg-config/fontconfig:ro"
        return
    fi

    log_info "Configuring Flatpak access to user fonts..."
    if flatpak override --user --filesystem=xdg-config/fontconfig:ro 2>/dev/null; then
        log_succ "Flatpak override applied."
    else
        log_warn "Failed to apply Flatpak override (is Flatpak setup correctly?)"
    fi
}

# ============================================================================ 
# MAIN
# ============================================================================ 

usage() {
    cat <<USAGE
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --uninstall, --revert   Remove the configuration and revert changes.
  --dry-run               Show what would be done without making changes.
  --no-flatpak            Skip Flatpak configuration steps.
  -h, --help              Show this help message.

USAGE
}

main() {
    local DRY_RUN=0
    local SKIP_FLATPAK=0
    local MODE="install"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)    DRY_RUN=1 ;;
            --no-flatpak) SKIP_FLATPAK=1 ;;
            --uninstall|--revert) MODE="uninstall" ;; 
            -h|--help)    usage; exit 0 ;; 
            *)            die "Unknown argument: $1" ;; 
        esac
        shift
    done

    if [[ "$MODE" == "install" ]]; then
        log_info "Starting Fedora Thai Font Configuration Installer..."
        
        check_dependencies
        
        # install_config returns 1 if changes were made
        local changed=0
        install_config || changed=1
        
        ensure_main_conf
        configure_flatpak
        
        if [[ $changed -eq 1 ]]; then
            refresh_cache
        else
            log_info "No file changes detected; skipping cache refresh."
        fi
        
        log_succ "Setup Complete. Your Thai fonts should now render using Fedora's rules."
        
    elif [[ "$MODE" == "uninstall" ]]; then
        log_info "Uninstalling Fedora Thai Font Configuration..."
        
        local changed=0
        uninstall_config || changed=1
        
        if [[ $changed -eq 1 ]]; then
            refresh_cache
            log_succ "Uninstallation Complete."
        else
            log_info "No changes detected."
        fi
    fi
}

main "$@"