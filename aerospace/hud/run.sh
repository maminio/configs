#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="$script_dir/AeroSpaceHud.app"
bin="$app/Contents/MacOS/AeroSpaceHud"
source="$script_dir/AeroSpaceHud.swift"
log_file="/tmp/aerospace-hud.log"
pid_file="/tmp/aerospace-hud.pid"
label="dev.aminmoradi.aerospace-hud"

needs_rebuild() {
  [[ ! -x "$bin" || "$source" -nt "$bin" || "$script_dir/config.toml" -nt "$bin" ]]
}

pid_is_stale() {
  [[ "$bin" -nt "$pid_file" || "$source" -nt "$pid_file" || "$script_dir/config.toml" -nt "$pid_file" ]]
}

if [[ -f "$pid_file" ]]; then
  old_pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" >/dev/null 2>&1; then
    if ! pid_is_stale; then
      exit 0
    fi

    launchctl remove "$label" >/dev/null 2>&1 || true
    kill "$old_pid" >/dev/null 2>&1 || true
    rm -f "$pid_file"
  fi
fi

existing_pid="$(pgrep -f "$bin" | head -n 1 || true)"
if [[ -n "$existing_pid" ]]; then
  if [[ -f "$pid_file" ]] && ! pid_is_stale; then
    echo "$existing_pid" >"$pid_file"
    exit 0
  fi

  launchctl remove "$label" >/dev/null 2>&1 || true
  kill "$existing_pid" >/dev/null 2>&1 || true
  rm -f "$pid_file"
fi

if needs_rebuild; then
  "$script_dir/build.sh"
fi

# Drop any legacy launchctl job. `launchctl submit` starts the binary without a
# window-server connection, so NSApp.run() returns immediately and the process
# exits — leaving no HUD. Launch through LaunchServices instead so the app joins
# the user's GUI session (required for its panels + menu-bar item).
launchctl remove "$label" >/dev/null 2>&1 || true

# Make sure no stale instance lingers before relaunching the fresh binary.
pkill -f "$bin" >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -f "$bin" >/dev/null 2>&1 || break
  sleep 0.1
done

open -g "$app"
sleep 0.7

pid="$(pgrep -f "$bin" | head -n 1 || true)"
if [[ -n "$pid" ]]; then
  echo "$pid" >"$pid_file"
fi
