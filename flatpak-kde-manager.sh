#!/usr/bin/env bash
# Manage Flatpak integration on Arch-based KDE systems.
# Provides setup (install/enable), revert (remove/disable), and status flows.

set -euo pipefail

# ============================================================================ 
# CONSTANTS & CONFIGURATION
# ============================================================================ 

readonly SCRIPT_NAME="${0##*/}"

# Core Arch Packages required for Flatpak + KDE integration
readonly REQUIRED_PACKAGES=(
  flatpak
  xdg-desktop-portal
  xdg-desktop-portal-kde
  kde-gtk-config
)

# Flathub Configuration
readonly FLATHUB_REMOTE_NAME="flathub"
readonly FLATHUB_REMOTE_URL="https://flathub.org/repo/flathub.flatpakrepo"

# KDE/Qt Theming Runtimes to ensure apps look native
readonly THEME_EXTENSION_REFS=(
  org.kde.PlatformTheme.QGnomePlatform//6.4
  org.kde.KStyle.Adwaita//6.4
)

# ============================================================================ 
# UTILS & LOGGING
# ============================================================================ 

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

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Required command '$1' not found. Please install it."
  fi
}

# ============================================================================ 
# CORE LOGIC
# ============================================================================ 

install_arch_packages() {
  log_info "Checking pacman packages..."
  local missing_pkgs=()
  
  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
      missing_pkgs+=("$pkg")
    fi
  done

  if [[ ${#missing_pkgs[@]} -eq 0 ]]; then
    log_succ "All required pacman packages are already installed."
    return
  fi

  log_info "Installing missing packages: ${missing_pkgs[*]}"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[DRY-RUN] Would run: sudo pacman -S --noconfirm ${missing_pkgs[*]}"
  else
    sudo pacman -S --needed --noconfirm "${missing_pkgs[@]}"
    log_succ "Packages installed."
  fi
}

ensure_flathub_remote() {
  log_info "Checking Flathub remote..."
  if flatpak remote-list --columns=name | grep -Fxq "$FLATHUB_REMOTE_NAME"; then
    log_succ "Flathub remote already configured."
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      log_info "[DRY-RUN] Would run: sudo flatpak remote-add --if-not-exists $FLATHUB_REMOTE_NAME $FLATHUB_REMOTE_URL"
    else
      sudo flatpak remote-add --if-not-exists "$FLATHUB_REMOTE_NAME" "$FLATHUB_REMOTE_URL"
      log_succ "Added Flathub remote."
    fi
  fi
}

install_theme_extensions() {
  log_info "Checking KDE integration runtimes..."
  if [[ ${#THEME_EXTENSION_REFS[@]} -eq 0 ]]; then return; fi
  
  local missing_refs=()
  for ref in "${THEME_EXTENSION_REFS[@]}"; do
    if ! flatpak info "$ref" >/dev/null 2>&1; then
      missing_refs+=("$ref")
    fi
  done

  if [[ ${#missing_refs[@]} -eq 0 ]]; then
    log_succ "Theme runtimes are already installed."
    return
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[DRY-RUN] Would run: flatpak install -y $FLATHUB_REMOTE_NAME ${missing_refs[*]}"
  else
    if flatpak install -y "$FLATHUB_REMOTE_NAME" "${missing_refs[@]}"; then
      log_succ "Theme runtimes installed."
    else
      log_warn "One or more theme runtimes failed to install."
    fi
  fi
}

remove_theme_extensions() {
  log_info "Removing KDE integration runtimes..."
  for ref in "${THEME_EXTENSION_REFS[@]}"; do
    if flatpak info "$ref" >/dev/null 2>&1; then
      if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY-RUN] Would run: flatpak uninstall -y $ref"
      else
        if flatpak uninstall -y "$ref" >/dev/null 2>&1; then
          log_succ "Removed $ref"
        else
          log_warn "Could not remove $ref (it may still be required)."
        fi
      fi
    else
      log_info "Skip $ref (not installed)"
    fi
  done
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[DRY-RUN] Would run: flatpak uninstall -y --unused"
  else
    flatpak uninstall -y --unused >/dev/null 2>&1 || true
  fi
}

maybe_remove_flathub() {
  log_info "Checking if Flathub remote can be removed..."
  if ! flatpak remote-list --columns=name | grep -Fxq "$FLATHUB_REMOTE_NAME"; then
    log_info "Flathub remote not present."
    return
  fi

  if (( KEEP_REMOTE )); then
    log_info "Keeping Flathub remote (--keep-remote used)."
    return
  fi

  # Check if any installed app uses Flathub
  if flatpak list --columns=origin | grep -Fxq "$FLATHUB_REMOTE_NAME"; then
    log_warn "Flathub is still in use by installed applications; keeping remote."
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      log_info "[DRY-RUN] Would run: sudo flatpak remote-delete $FLATHUB_REMOTE_NAME"
    else
      sudo flatpak remote-delete "$FLATHUB_REMOTE_NAME"
      log_succ "Removed Flathub remote."
    fi
  fi
}

remove_arch_packages() {
  log_info "Removing pacman packages..."
  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if pacman -Qi "$pkg" >/dev/null 2>&1; then
      if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY-RUN] Would run: sudo pacman -Rs --noconfirm $pkg"
      else
        if sudo pacman -Rs --noconfirm "$pkg" >/dev/null 2>&1; then
          log_succ "Removed $pkg"
        else
          log_warn "Could not remove $pkg (likely required by other packages)."
        fi
      fi
    else
      log_info "Skip $pkg (not installed)"
    fi
  done
}

report_status() {
  printf "\n=== System Status Report ===\n"
  
  log_info "Pacman Packages:"
  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if pacman -Qi "$pkg" >/dev/null 2>&1; then
      printf "  ${C_GREEN}✔${C_RESET} %s\n" "$pkg"
    else
      printf "  ${C_RED}✘${C_RESET} %s\n" "$pkg"
    fi
  done

  log_info "Flathub Remote:"
  if flatpak remote-list --columns=name | grep -Fxq "$FLATHUB_REMOTE_NAME"; then
    printf "  ${C_GREEN}✔${C_RESET} Present\n"
  else
    printf "  ${C_RED}✘${C_RESET} Not configured\n"
  fi

  log_info "Theme Runtimes:"
  for ref in "${THEME_EXTENSION_REFS[@]}"; do
    if flatpak info "$ref" >/dev/null 2>&1; then
      printf "  ${C_GREEN}✔${C_RESET} %s\n" "$ref"
    else
      printf "  ${C_RED}✘${C_RESET} %s\n" "$ref"
    fi
  done
  printf "\n"
}

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --setup        Install Flatpak tooling, add Flathub, and install KDE theme runtimes (default).
  --revert       Undo the setup by removing theme runtimes, optionally Flathub, and pacman packages.
  --status       Report what components are currently installed/configured.
  --keep-remote  When reverting, leave the Flathub remote in place if present.
  --dry-run      Preview changes without applying them.
  -h, --help     Show this message.
USAGE
}

# ============================================================================ 
# MAIN
# ============================================================================ 

MODE="setup"
KEEP_REMOTE=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --setup)       MODE="setup"; shift ;;
    --revert)      MODE="revert"; shift ;;
    --status)      MODE="status"; shift ;;
    --keep-remote) KEEP_REMOTE=1; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "Unknown option: $1" ;;
  esac
done

require_command sudo
require_command pacman
require_command flatpak

case "$MODE" in
  setup)
    install_arch_packages
    ensure_flathub_remote
    install_theme_extensions
    log_succ "Setup complete. KDE portals will sync theme changes for Flatpak apps."
    ;;
  revert)
    remove_theme_extensions
    maybe_remove_flathub
    remove_arch_packages
    log_succ "Revert complete. Reboot or relog if portals still cache themes."
    ;;
  status)
    report_status
    ;;
esac

