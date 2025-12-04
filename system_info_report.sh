#!/usr/bin/env bash
# Collects a safe snapshot of key system information into a text file for sharing with an LLM.

set -uo pipefail

OUT="${1:-system_report_$(hostname 2>/dev/null || echo host)_$(date +%Y%m%d_%H%M%S).txt}"

touch "$OUT" 2>/dev/null || { echo "Cannot write to $OUT" >&2; exit 1; }
: > "$OUT"

append() { printf "%s\n" "$*" >>"$OUT"; }

section() {
  append ""
  append "### $*"
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

run_cmd() {
  local cmd="$1"
  shift || true
  if has_cmd "$cmd"; then
    append ""
    append "\$ ${cmd} $*"
    "$cmd" "$@" >>"$OUT" 2>&1
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
    cat "$file" >>"$OUT"
  else
    append ""
    append "SKIP: cannot read $file"
  fi
}

append "System information snapshot"
append "Generated: $(date -Is)"
append "Host: $(hostname 2>/dev/null || echo unknown)"
append "User: ${USER:-unknown}"
append "Output file: $(realpath "$OUT" 2>/dev/null || echo "$OUT")"

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
  grep -m1 "model name" /proc/cpuinfo >>"$OUT"
fi
run_cmd free -h
run_cmd swapon --show
run_cmd lsblk -o NAME,TYPE,FSTYPE,SIZE,FSUSED,FSUSE%,MOUNTPOINT
run_cmd df -h -x tmpfs -x devtmpfs
if has_cmd lspci; then
  append ""
  append "\$ lspci | grep -iE \"vga|3d|display\""
  lspci | grep -iE "vga|3d|display" >>"$OUT" 2>&1
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
  ps -eo pid,comm,%cpu,%mem --sort=-%mem | head -n 20 >>"$OUT" 2>&1
  append ""
  append "\$ ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 20"
  ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 20 >>"$OUT" 2>&1
else
  append ""
  append "SKIP: ps not found"
fi

section "Packages"
if has_cmd dpkg-query; then
  append ""
  append "Installed packages (count):"
  dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | wc -l >>"$OUT"
fi
if has_cmd rpm; then
  append ""
  append "Installed RPMs (count):"
  rpm -qa 2>/dev/null | wc -l >>"$OUT"
fi
if has_cmd pacman; then
  append ""
  append "Installed pacman packages (count):"
  pacman -Qq 2>/dev/null | wc -l >>"$OUT"
fi

section "Kernel parameters"
capture_file "/proc/cmdline"

section "Locale"
run_cmd locale

append ""
append "Done."
