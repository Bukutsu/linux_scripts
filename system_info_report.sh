#!/usr/bin/env bash
# Collects a safe snapshot of key system information into a text file.
# Useful for sharing with LLMs or support forums for troubleshooting.

set -uo pipefail

# ============================================================================ 
# UTILS & LOGGING
# ============================================================================ 

if [[ -t 2 ]]; then
    readonly C_GREEN='\033[0;32m'
    readonly C_BLUE='\033[0;34m'
    readonly C_YELLOW='\033[0;33m'
    readonly C_RESET='\033[0m'
else
    readonly C_GREEN=''
    readonly C_BLUE=''
    readonly C_YELLOW=''
    readonly C_RESET=''
fi

log_info() { printf "${C_BLUE}[INFO]${C_RESET} %s\n" "$*" >&2; }
log_succ() { printf "${C_GREEN}[OK]${C_RESET}   %s\n" "$*" >&2; }
log_warn() { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$*" >&2; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<USAGE
Usage: $(basename "$0") [OPTIONS] 

Options:
  -o, --output FILE   Specify output file path (default: auto-generated timestamped file).
  --stdout            Print report to standard output instead of a file.
  -h, --help          Show this help message.
USAGE
}

# ============================================================================ 
# CONFIGURATION
# ============================================================================ 

OUTPUT_MODE="file"
OUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      OUT_FILE="$2"
      shift 2
      ;; 
    --stdout)
      OUTPUT_MODE="stdout"
      shift
      ;; 
    -h|--help)
      usage
      exit 0
      ;; 
    *)
      printf "Unknown option: %s\n" "$1" >&2
      usage
      exit 1
      ;; 
  esac
done

if [[ "$OUTPUT_MODE" == "file" ]]; then
  if [[ -z "$OUT_FILE" ]]; then
    OUT_FILE="system_report_$(hostname 2>/dev/null || echo host)_$(date +%Y%m%d_%H%M%S).txt"
  fi
  
  # Ensure we can write to the file
  touch "$OUT_FILE" 2>/dev/null || {
    printf "Error: Cannot write to %s\n" "$OUT_FILE" >&2
    exit 1
  }
  
  # Trap to clean up empty/partial file on error (optional, but good for robustness)
  trap '[[ -s "$OUT_FILE" ]] || rm -f "$OUT_FILE"' EXIT
  
  log_info "Generating system report to: $OUT_FILE"
else
  log_info "Generating system report to stdout..."
fi

# Helper to append to the correct destination
append() {
  if [[ "$OUTPUT_MODE" == "file" ]]; then
    printf "%s\n" "$*" >> "$OUT_FILE"
  else
    printf "%s\n" "$*"
  fi
}

section() {
  append ""
  append "### $*"
  [[ "$OUTPUT_MODE" == "file" ]] && log_info "Processing section: $*"
}

run_cmd() {
  local cmd="$1"
  shift || true
  if has_cmd "$cmd"; then
    append ""
    append "\$ ${cmd} $*"
    if [[ "$OUTPUT_MODE" == "file" ]]; then
      "$cmd" "$@" >> "$OUT_FILE" 2>&1
    else
      "$cmd" "$@" 2>&1
    fi
  else
    append ""
    append "SKIP: $cmd not found"
  fi
}

capture_file() {
  local file="$1"
  if [ -r "$file" ]; then
    append ""
    append "file: $file"
    if [[ "$OUTPUT_MODE" == "file" ]]; then
      cat "$file" >> "$OUT_FILE"
    else
      cat "$file"
    fi
  else
    append ""
    append "SKIP: cannot read $file"
  fi
}

# ============================================================================ 
# REPORT GENERATION
# ============================================================================ 

append "System information snapshot"
append "Generated: $(date -Is)"
append "Host: $(hostname 2>/dev/null || echo unknown)"
append "User: ${USER:-unknown}"
if [[ "$OUTPUT_MODE" == "file" ]]; then
  append "Output file: $(realpath "$OUT_FILE" 2>/dev/null || echo "$OUT_FILE")"
fi

section "OS and kernel"
capture_file "/etc/os-release"
run_cmd lsb_release -a
run_cmd uname -a
run_cmd uptime -p
run_cmd who -b

section "Hardware"
run_cmd systemd-detect-virt
run_cmd lscpu
if ! has_cmd lscpu && [ -r /proc/cpuinfo ]; then
  append ""
  append "CPU (from /proc/cpuinfo model name):"
  if [[ "$OUTPUT_MODE" == "file" ]]; then
    grep -m1 "model name" /proc/cpuinfo >> "$OUT_FILE"
  else
    grep -m1 "model name" /proc/cpuinfo
  fi
fi
run_cmd free -h
run_cmd swapon --show
run_cmd lsblk -o NAME,TYPE,FSTYPE,SIZE,FSUSED,FSUSE%,MOUNTPOINT
run_cmd df -h -x tmpfs -x devtmpfs
if has_cmd lspci; then
  append ""
  append "\$ lspci | grep -iE \"vga|3d|display\""
  if [[ "$OUTPUT_MODE" == "file" ]]; then
    lspci | grep -iE "vga|3d|display" >> "$OUT_FILE" 2>&1
  else
    lspci | grep -iE "vga|3d|display" 2>&1
  fi
else
  append ""
  append "SKIP: lspci not found"
fi

section "Boot and services"
run_cmd systemctl list-units --type=service --state=running --no-pager --no-legend
run_cmd systemctl get-default
run_cmd journalctl -b -n 50 --no-pager

section "Network"
run_cmd ip -brief address
run_cmd ip route
run_cmd ss -tuln
capture_file "/etc/resolv.conf"

section "Processes"
if has_cmd ps; then
  append ""
  append "\$ ps -eo pid,comm,%cpu,%mem --sort=-%mem | head -n 20"
  if [[ "$OUTPUT_MODE" == "file" ]]; then
    ps -eo pid,comm,%cpu,%mem --sort=-%mem | head -n 20 >> "$OUT_FILE" 2>&1
    append ""
    append "\$ ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 20"
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 20 >> "$OUT_FILE" 2>&1
  else
    ps -eo pid,comm,%cpu,%mem --sort=-%mem | head -n 20 2>&1
    append ""
    append "\$ ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 20"
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 20 2>&1
  fi
else
  append ""
  append "SKIP: ps not found"
fi

section "Packages"
if has_cmd dpkg-query; then
  append ""
  append "Installed packages (count):"
  if [[ "$OUTPUT_MODE" == "file" ]]; then
     dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | wc -l >> "$OUT_FILE"
  else
     dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | wc -l
  fi
fi
if has_cmd rpm; then
  append ""
  append "Installed RPMs (count):"
  if [[ "$OUTPUT_MODE" == "file" ]]; then
     rpm -qa 2>/dev/null | wc -l >> "$OUT_FILE"
  else
     rpm -qa 2>/dev/null | wc -l
  fi
fi
if has_cmd pacman; then
  append ""
  append "Installed pacman packages (count):"
  if [[ "$OUTPUT_MODE" == "file" ]]; then
     pacman -Qq 2>/dev/null | wc -l >> "$OUT_FILE"
  else
     pacman -Qq 2>/dev/null | wc -l
  fi
fi

section "Kernel parameters"
capture_file "/proc/cmdline"

section "Locale"
run_cmd locale

if [[ "$OUTPUT_MODE" == "file" ]]; then
  append ""
  append "Done."
  log_succ "Report saved to $OUT_FILE"
else
  log_succ "Report generation complete."
fi