#!/bin/bash
# Cleanup script for fontconfig
cd "${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig/conf.d/" || exit

# Remove all symlinks (which are likely the system copies)
find . -type l -delete

echo "Cleaned up symlinks."
