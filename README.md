# Linux Scripts Toolkit

A small collection of Bash utilities I use to smooth out daily Linux maintenance tasks. Each script is designed to be safe to rerun, verbose about the work it performs, and undoable where practical.

## Getting Started

```bash
# Clone the repo and enter it
git clone <repo-url>
cd linux_scripts

# Make the scripts executable once
chmod +x *.sh
```

Most scripts log their progress to stderr so you can redirect noise away from pipelines. They all assume `bash` 5+, GNU coreutils, and a POSIX-like environment.

## Scripts

### `steam_cache_relocator.sh`

Moves shader caches (`shadercache`, `steamshadercache`) and Proton prefixes (`compatdata`) from every secondary Steam library into the primary library under `$HOME/.local/share/Steam/steamapps`. After moving data it creates symlinks in the secondary libraries so future writes land on the faster drive.

Key features:
- Auto-detects every library defined in `steamapps/libraryfolders.vdf`, including libraries on other drives.
- Uses `rsync --info=progress2` to show copy progress when attached to a TTY (pass `--no-progress` to silence).
- Writes a manifest in `steamapps/.steam_cache_relocator/` so `--undo` can restore directories and put data back if the script moved files away from a slower drive.

Usage:
```bash
./steam_cache_relocator.sh                # relocate caches to the home library
./steam_cache_relocator.sh /path/to/lib   # specify the primary Steam directory
./steam_cache_relocator.sh --no-progress  # hide the rsync progress meter
./steam_cache_relocator.sh --undo         # restore directories from the manifest
```

Dependencies: `rsync`, `sha1sum`, `find`, Steam for Linux. If a previous run produced a manifest you must undo before relocating again.

### `flatpak-kde-manager.sh`

One-stop helper for Arch-based KDE systems. Installs Flatpak, the KDE xdg portal stack, and KDE GTK integration packages, and can undo those changes later. The script also reports the current state of key packages, theme runtimes, and the Flathub remote.

Usage:
```bash
./flatpak-kde-manager.sh              # run setup (default)
./flatpak-kde-manager.sh --revert      # undo the setup flow
./flatpak-kde-manager.sh --status      # report installed components
./flatpak-kde-manager.sh --revert --keep-remote  # undo but leave Flathub configured
```

Requires `pacman`, `sudo`, and `flatpak`. Safe to rerun; each mode skips work that is already in the requested state.

### `noto_fontconfig_installer.sh`

Installs a fontconfig snippet that promotes the Noto family (including Thai coverage and emoji) for the generic `serif`, `sans-serif`, and `monospace` fallbacks. The script can target either system-wide directories (default) or the per-user config tree.

Usage:
```bash
sudo ./noto_fontconfig_installer.sh --install          # install system-wide
./noto_fontconfig_installer.sh --install --user        # install for current user only
./noto_fontconfig_installer.sh --remove --user         # remove the per-user config
./noto_fontconfig_installer.sh --status --system       # report state of the system config
./noto_fontconfig_installer.sh --install --dry-run     # preview actions without changes
./noto_fontconfig_installer.sh --install --no-font-install  # skip package installation
./noto_fontconfig_installer.sh --install --user --flatpak   # expose config to Flatpak apps
```

Dependencies: `fc-cache` (optional but recommended). The script checks for key Noto families and, when run as root, will auto-install them using `pacman`, `apt`, `dnf/yum`, `zypper`, or `emerge` if they are missing (pass `--no-font-install` to skip). Installing to `/etc/fonts` requires root; the script refuses to escalate itself so invoke with `sudo` when targeting the system. Use `--flatpak` with a user install to apply a `flatpak override` that mounts the host fontconfig into all Flatpak apps.

## Contributing / Extending

Keep new scripts idempotent and fail-fast (`set -euo pipefail`). Prefer explicit logging so users can tell what changed. If a script alters system state, add a complementary undo or revert path where feasible. Pull requests that follow those guidelines are welcome.

## License

Released under the MIT License. See the `LICENSE` file for full text.
