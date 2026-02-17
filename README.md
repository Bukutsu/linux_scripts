# 🛠️ System Config Scripts

A collection of shell scripts for Linux system configuration, maintenance, and troubleshooting — primarily targeting Arch-based (CachyOS) and Fedora systems with KDE Plasma.

## Scripts

---

### 🎮 `steam_cache_relocator.sh`

Relocates Steam shader and Proton caches from secondary Steam libraries to the primary Steam directory using symlinks. Useful when you have games installed across multiple drives but want caches consolidated on a faster disk.

**Features:**
- Relocate mode with rsync and atomic symlink creation
- Full undo/restore with manifest-based state tracking
- Disk space verification with 10% safety margin
- Lock file to prevent concurrent execution
- Steam process detection (skip with `--force`)
- Dry-run preview

**Usage:**
```bash
./steam_cache_relocator.sh                    # Relocate caches
./steam_cache_relocator.sh --dry-run          # Preview changes
./steam_cache_relocator.sh --undo             # Restore original layout
./steam_cache_relocator.sh ~/.steam/steam     # Custom Steam directory
```

---

### 📦 `flatpak-kde-manager.sh`

Manages Flatpak integration on Arch-based KDE systems — installs required packages, configures Flathub, and sets up KDE/Qt theming runtimes so Flatpak apps look native.

**Features:**
- Setup, revert, and status reporting modes
- Installs `flatpak`, `xdg-desktop-portal`, `xdg-desktop-portal-kde`, `kde-gtk-config`
- Configures KDE theme extensions (`QGnomePlatform`, `Adwaita` KStyle)
- Safe revert that checks for apps still using Flathub before removing the remote
- Dry-run support

**Usage:**
```bash
./flatpak-kde-manager.sh --setup       # Install and configure everything
./flatpak-kde-manager.sh --revert      # Undo setup
./flatpak-kde-manager.sh --status      # Show current integration status
./flatpak-kde-manager.sh --dry-run     # Preview changes
```

---

### 🇹🇭 `install_fedora_thai_config.sh`

Installs Fedora's official fontconfig rules for Thai language support into the user's home directory. Distro-agnostic — works on any Linux distribution with Noto Thai fonts installed.

**Features:**
- Idempotent — skips writing if config is already up to date
- Atomic file writes with backup of existing configs
- Auto-detects package manager and suggests font install commands
- Creates a proper `fonts.conf` with `conf.d` include if missing
- Flatpak font access override
- Force-reset mode to start fresh
- Install and uninstall modes

**Usage:**
```bash
./install_fedora_thai_config.sh                # Install Thai font rules
./install_fedora_thai_config.sh --uninstall    # Remove configuration
./install_fedora_thai_config.sh --force-reset  # Backup and start fresh
./install_fedora_thai_config.sh --dry-run      # Preview changes
./install_fedora_thai_config.sh --no-flatpak   # Skip Flatpak override
```

---

### 📊 `system_info_report.sh`

Collects a comprehensive, safe snapshot of system information into a text file. Ideal for sharing with LLMs or support forums when troubleshooting.

**Sections collected:**
- OS, kernel, and uptime
- Hardware (CPU, memory, GPU, disks)
- Boot services and recent journal entries
- Network configuration
- Top processes by CPU and memory
- Installed package counts
- Kernel parameters and locale

**Usage:**
```bash
./system_info_report.sh                      # Save to timestamped file
./system_info_report.sh -o report.txt        # Save to specific file
./system_info_report.sh --stdout             # Print to terminal
```

---

### 🔤 `cleanup_fonts.sh`

Quick utility to remove symlinks from the user's fontconfig `conf.d` directory — useful for clearing out system-copied symlinks that may conflict with custom font configurations.

**Usage:**
```bash
./cleanup_fonts.sh
```

---

### 📷 `howdy_camera.te` / `howdy_camera.pp`

SELinux policy module that grants the display manager (`xdm_t`) permission to memory-map V4L2 camera devices. Required for [Howdy](https://github.com/boltgolt/howdy) facial recognition to work with SELinux enforcing.

**The `.te` source grants:**
```
allow xdm_t v4l_device_t:chr_file map;
```

> **Note:** The `.pp` is the compiled policy binary. To recompile from source:
> ```bash
> checkmodule -M -m -o howdy_camera.mod howdy_camera.te
> semodule_package -o howdy_camera.pp -m howdy_camera.mod
> sudo semodule -i howdy_camera.pp
> ```

---

## Requirements

| Script | Dependencies |
|--------|-------------|
| `steam_cache_relocator.sh` | `rsync`, `sha1sum`, Steam installed |
| `flatpak-kde-manager.sh` | `pacman`, `flatpak`, `sudo` |
| `install_fedora_thai_config.sh` | `fc-list`/`fc-cache` (fontconfig), Noto Thai fonts |
| `system_info_report.sh` | Standard Linux utilities (`lscpu`, `ip`, `ps`, etc.) |
| `cleanup_fonts.sh` | `find` |
| `howdy_camera.*` | SELinux tools (`checkmodule`, `semodule`) |

## License

[MIT](LICENSE) © bukutsu
