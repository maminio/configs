#!/usr/bin/env bash
set -euo pipefail

# Build the HUD bundle and link it into /Applications so it shows up in
# Launchpad / Spotlight and can be launched by hand. A symlink (not a copy) is
# used so every rebuild is picked up with no reinstall. AeroSpace still launches
# the binary directly via hud/run.sh on startup; this is for visibility + manual
# launch.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="$script_dir/AeroSpaceHud.app"
dest="/Applications/AeroSpace HUD.app"

"$script_dir/build.sh"

if [[ -e "$dest" || -L "$dest" ]]; then
  rm -rf "$dest"
fi
ln -s "$app" "$dest"

echo "Linked: $dest -> $app"
echo "Launch it from Launchpad/Spotlight ('AeroSpace HUD'), or: open \"$dest\""
