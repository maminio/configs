#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
module_cache="${TMPDIR:-/tmp}/aerospace-hud-module-cache"
app_dir="$script_dir/AeroSpaceHud.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

mkdir -p "$module_cache"
mkdir -p "$macos_dir"
mkdir -p "$resources_dir"

swiftc "$script_dir/AeroSpaceHud.swift" \
  -module-cache-path "$module_cache" \
  -framework AppKit \
  -o "$macos_dir/AeroSpaceHud"

cat >"$contents_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>AeroSpaceHud</string>
  <key>CFBundleIdentifier</key>
  <string>dev.aminmoradi.aerospace-hud</string>
  <key>CFBundleName</key>
  <string>AeroSpace HUD</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

cp "$script_dir/config.toml" "$resources_dir/config.toml"
/usr/bin/codesign --force --deep --sign - "$app_dir" >/dev/null
