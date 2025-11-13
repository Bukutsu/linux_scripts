# Noto Fontconfig Installer - Quick Reference

## Common Operations

### Installation

#### Install for current user (recommended)
```bash
./noto_fontconfig_installer.sh --user
```

#### Install system-wide (requires root)
```bash
sudo ./noto_fontconfig_installer.sh --system
```

#### Install with Flatpak support
```bash
./noto_fontconfig_installer.sh --user --flatpak
```

#### Test what would happen (dry-run)
```bash
./noto_fontconfig_installer.sh --user --dry-run
```

### Status Check

#### Check if configuration is active
```bash
./noto_fontconfig_installer.sh --status --user
```

#### Check system-wide configuration
```bash
./noto_fontconfig_installer.sh --status --system
```

### Removal

#### Remove user configuration
```bash
./noto_fontconfig_installer.sh --remove --user
```

#### Remove system configuration
```bash
sudo ./noto_fontconfig_installer.sh --remove --system
```

### Advanced Options

#### Force overwrite existing files
```bash
./noto_fontconfig_installer.sh --user --force
```

#### Skip automatic font installation
```bash
./noto_fontconfig_installer.sh --user --no-font-install
```

#### Skip font cache refresh (faster)
```bash
./noto_fontconfig_installer.sh --user --no-cache
```

#### Enable debug logging
```bash
./noto_fontconfig_installer.sh --user --debug
```

### Troubleshooting

#### Check what's wrong
```bash
# First, check status
./noto_fontconfig_installer.sh --status --user

# If issues, run with debug
./noto_fontconfig_installer.sh --status --user --debug
```

#### Test without making changes
```bash
# Always safe to run
./noto_fontconfig_installer.sh --dry-run --user
```

#### Force reinstall
```bash
# Remove old, install new
./noto_fontconfig_installer.sh --remove --user
./noto_fontconfig_installer.sh --install --user
```

#### Restore from backup
```bash
# Backups are created automatically with timestamp
cd ~/.config/fontconfig/conf.avail
ls -lt *.bak.*
# Manually restore: mv 60-noto-prefer-thai.conf.bak.YYYYMMDD_HHMMSS 60-noto-prefer-thai.conf
```

## Exit Codes

| Code | Meaning                    | Action                                      |
|------|----------------------------|---------------------------------------------|
| 0    | Success                    | Everything worked                           |
| 1    | General error              | Check error message                         |
| 2    | Permission denied          | Run with sudo for system installs           |
| 3    | Dependency missing         | Install required package (shown in error)   |
| 4    | Lock failed                | Another instance running, wait and retry    |
| 5    | Validation failed          | File/XML validation issue, report bug       |

## File Locations

### User Installation
- Config: `~/.config/fontconfig/conf.avail/60-noto-prefer-thai.conf`
- Active: `~/.config/fontconfig/conf.d/60-noto-prefer-thai.conf` (symlink)
- Backups: `~/.config/fontconfig/conf.avail/*.bak.*`

### System Installation
- Config: `/etc/fonts/conf.avail/60-noto-prefer-thai.conf`
- Active: `/etc/fonts/conf.d/60-noto-prefer-thai.conf` (symlink)
- Backups: `/etc/fonts/conf.avail/*.bak.*`

### Lock Files
- User: `/tmp/noto_fontconfig_installer.sh.user.lock`
- System: `/tmp/noto_fontconfig_installer.sh.system.lock`

## Required Fonts

The script needs these Noto fonts installed:
- Noto Sans
- Noto Sans Thai
- Noto Sans Mono
- Noto Serif
- Noto Serif Thai
- Noto Color Emoji

The script will attempt to auto-install these if run as root (unless `--no-font-install` is used).

## Distribution-Specific Packages

### Arch Linux / Manjaro
```bash
sudo pacman -S noto-fonts noto-fonts-cjk noto-fonts-extra
```

### Ubuntu / Debian
```bash
sudo apt install fonts-noto-core fonts-noto-color-emoji fonts-noto-unhinted
```

### Fedora / RHEL / CentOS
```bash
sudo dnf install google-noto-sans-fonts google-noto-serif-fonts \
  google-noto-sans-thai-fonts google-noto-emoji-color-fonts google-noto-mono-fonts
```

### openSUSE
```bash
sudo zypper install google-noto-sans-fonts google-noto-serif-fonts \
  google-noto-sans-thai-fonts google-noto-emoji-color-fonts google-noto-mono-fonts
```

### Alpine Linux
```bash
sudo apk add font-noto font-noto-emoji font-noto-thai
```

### Gentoo
```bash
sudo emerge media-fonts/noto media-fonts/noto-emoji
```

## FAQ

### Q: Which should I use, --user or --system?
**A:** Use `--user` unless you want all users on the system to have this configuration. User installs don't require root.

### Q: Will this break my existing font configuration?
**A:** No. The script creates a backup before making changes. You can also test with `--dry-run` first.

### Q: Do I need to restart my applications?
**A:** Most applications will pick up the changes automatically. Some (like terminals) may need restart.

### Q: How do I undo the changes?
**A:** Run `./noto_fontconfig_installer.sh --remove --user` (or `--system`)

### Q: What does --flatpak do?
**A:** It allows Flatpak apps to see your fontconfig and fonts directory. Only works with `--user`.

### Q: Can I run this on a server without X11?
**A:** Yes. The script works in headless environments. Font rendering will work for any GUI apps launched later.

### Q: The script says "lock failed". What do I do?
**A:** Another instance is running. Wait for it to complete (max 30 seconds) or check for stuck processes.

### Q: How do I enable emoji support?
**A:** This is automatic when Noto Color Emoji is installed. The config prioritizes it for emoji rendering.

### Q: Does this affect monospace fonts in my terminal?
**A:** Yes, it sets Noto Sans Mono as preferred, but your terminal's font setting takes precedence.

## Integration Examples

### With system deployment scripts
```bash
#!/bin/bash
# Deploy script
./noto_fontconfig_installer.sh --user --no-cache
# Other setup steps...
fc-cache -f  # Refresh once at the end
```

### With dotfiles repository
```bash
# In your dotfiles install script
if [ -f ~/dotfiles/noto_fontconfig_installer.sh ]; then
  ~/dotfiles/noto_fontconfig_installer.sh --user --no-font-install
fi
```

### With Ansible
```yaml
- name: Install Noto fontconfig
  command: /path/to/noto_fontconfig_installer.sh --user
  become: yes
  become_user: "{{ user }}"
```

### With Docker/Containers
```dockerfile
RUN ./noto_fontconfig_installer.sh --system --no-cache
```

## Tips & Tricks

1. **Always test first**: Use `--dry-run` to preview changes
2. **Check status regularly**: Run `--status` to verify configuration
3. **Debug mode helps**: Add `--debug` when reporting issues
4. **Backups are automatic**: Look for `.bak.*` files if you need to rollback
5. **Force when needed**: Use `--force` to overwrite modified configs
6. **Skip cache for speed**: Use `--no-cache` in scripts, run `fc-cache` manually at end

## Getting Help

```bash
# Built-in help
./noto_fontconfig_installer.sh --help

# Check version/script info
head -n 20 ./noto_fontconfig_installer.sh

# Report issues with debug output
./noto_fontconfig_installer.sh --debug --dry-run --user > debug.log 2>&1
```
