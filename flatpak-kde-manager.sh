#!/usr/bin/env bash
# Manage Flatpak integration on Arch-based KDE systems.
# Provides both setup (install/enable) and revert (remove/disable) flows.

set -euo pipefail

REQUIRED_PACKAGES=(
  flatpak
  xdg-desktop-portal
  xdg-desktop-portal-kde
  kde-gtk-config
)

FLATHUB_REMOTE_NAME="flathub"
FLATHUB_REMOTE_URL="https://flathub.org/repo/flathub.flatpakrepo"

THEME_EXTENSION_REFS=(
  org.kde.PlatformTheme.QGnomePlatform//6.4
  org.kde.KStyle.Adwaita//6.4
)

mode="setup"
keep_remote=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--setup|--revert|--status] [--keep-remote]

Options:
  --setup        Install Flatpak tooling, add Flathub, and install KDE theme runtimes (default).
  --revert       Undo the setup by removing theme runtimes, optionally Flathub, and pacman packages.
  --status       Report what components are currently installed/configured.
  --keep-remote  When reverting, leave the Flathub remote in place if present.
  -h, --help     Show this message.
USAGE
}

log_step() {
  printf '\n==> %s\n' "$1"
}

log_info() {
  printf '    %s\n' "$1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required command "%s" not found.\n' "$1" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --setup)
      mode="setup"
      shift
      ;;
    --revert)
      mode="revert"
      shift
      ;;
    --status)
      mode="status"
      shift
      ;;
    --keep-remote)
      keep_remote=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      printf 'Unknown option: %s\n' "$1" >&2
      usage
      exit 1
      ;;
    *)
      printf 'Unexpected argument: %s\n' "$1" >&2
      usage
      exit 1
      ;;
  esac
done

require_command sudo
require_command pacman
require_command flatpak

install_arch_packages() {
  log_step "Installing required pacman packages"
  sudo pacman -S --needed --noconfirm "${REQUIRED_PACKAGES[@]}"
}

ensure_flathub_remote() {
  log_step "Ensuring Flathub remote is present"
  if flatpak remote-list --columns=name | grep -Fxq "$FLATHUB_REMOTE_NAME"; then
    log_info "Flathub remote already configured"
  else
    sudo flatpak remote-add --if-not-exists "$FLATHUB_REMOTE_NAME" "$FLATHUB_REMOTE_URL"
    log_info "Added Flathub remote"
  fi
}

install_theme_extensions() {
  log_step "Installing KDE integration runtimes (idempotent)"
  if [[ ${#THEME_EXTENSION_REFS[@]} -eq 0 ]]; then
    return
  fi
  if flatpak install -y "$FLATHUB_REMOTE_NAME" "${THEME_EXTENSION_REFS[@]}"; then
    log_info "Theme runtimes installed or already present"
  else
    printf 'Warning: one or more theme runtimes failed to install.\n' >&2
  fi
}

remove_theme_extensions() {
  log_step "Removing KDE integration runtimes"
  for ref in "${THEME_EXTENSION_REFS[@]}"; do
    if flatpak info "$ref" >/dev/null 2>&1; then
      if flatpak uninstall -y "$ref" >/dev/null 2>&1; then
        log_info "Removed $ref"
      else
        printf 'Could not remove %s (it may still be required).\n' "$ref" >&2
      fi
    else
      log_info "Skip $ref (not installed)"
    fi
  done
  flatpak uninstall -y --unused >/dev/null 2>&1 || true
}

maybe_remove_flathub() {
  log_step "Checking whether Flathub remote can be removed"
  if ! flatpak remote-list --columns=name | grep -Fxq "$FLATHUB_REMOTE_NAME"; then
    log_info "Flathub remote not present"
    return
  fi
  if (( keep_remote )); then
    log_info "--keep-remote supplied; leaving Flathub in place"
    return
  fi
  if flatpak list --columns=origin | grep -Fxq "$FLATHUB_REMOTE_NAME"; then
    log_info "Flathub still in use; keeping remote"
  else
    sudo flatpak remote-delete "$FLATHUB_REMOTE_NAME"
    log_info "Removed Flathub remote"
  fi
}

remove_arch_packages() {
  log_step "Removing pacman packages installed by setup"
  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if pacman -Qi "$pkg" >/dev/null 2>&1; then
      if sudo pacman -Rs --noconfirm "$pkg" >/dev/null 2>&1; then
        log_info "Removed $pkg"
      else
        printf 'Could not remove %s (likely required elsewhere).\n' "$pkg" >&2
      fi
    else
      log_info "Skip $pkg (not installed)"
    fi
  done
}

report_status() {
  log_step "Pacman packages"
  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if pacman -Qi "$pkg" >/dev/null 2>&1; then
      log_info "$pkg: installed"
    else
      log_info "$pkg: missing"
    fi
  done

  log_step "Flathub remote"
  if flatpak remote-list --columns=name | grep -Fxq "$FLATHUB_REMOTE_NAME"; then
    log_info "Present"
  else
    log_info "Not configured"
  fi

  log_step "Theme runtimes"
  for ref in "${THEME_EXTENSION_REFS[@]}"; do
    if flatpak info "$ref" >/dev/null 2>&1; then
      log_info "$ref: installed"
    else
      log_info "$ref: missing"
    fi
  done
}

perform_setup() {
  install_arch_packages
  ensure_flathub_remote
  install_theme_extensions
  log_step "Setup complete. KDE portals will sync theme changes for Flatpak apps"
}

perform_revert() {
  remove_theme_extensions
  maybe_remove_flathub
  remove_arch_packages
  log_step "Revert complete. Reboot or relog if portals still cache themes"
}

case "$mode" in
  setup)
    perform_setup
    ;;
  revert)
    perform_revert
    ;;
  status)
    report_status
    ;;
  *)
    printf 'Unknown mode: %s\n' "$mode" >&2
    exit 1
    ;;
esac
