#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="$script_dir/AeroSpaceSwitcher.app"
bin="$app/Contents/MacOS/AeroSpaceSwitcher"
source="$script_dir/AeroSpaceSwitcher.swift"
log_file="/tmp/aerospace-switcher.log"
pid_file="/tmp/aerospace-switcher.pid"
label="dev.aminmoradi.aerospace-switcher"

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

launchctl remove "$label" >/dev/null 2>&1 || true
launchctl submit -l "$label" -o "$log_file" -e "$log_file" -- "$bin"
sleep 0.7

pid="$(pgrep -f "$bin" | head -n 1 || true)"
if [[ -n "$pid" ]]; then
  echo "$pid" >"$pid_file"
fi
