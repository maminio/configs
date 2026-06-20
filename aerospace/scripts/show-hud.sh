#!/usr/bin/env bash
set -euo pipefail

aerospace_bin="${AEROSPACE_BIN:-aerospace}"
state_file="/tmp/aerospace-hud-focused-workspace"
show_file="/tmp/aerospace-mission-control-toggle"
hud_run="/Users/aminmoradi/workspace/configs/aerospace/hud/run.sh"

workspace="$("$aerospace_bin" list-workspaces --focused 2>/dev/null | awk '/^w[1-9][0-9]$/ { print; exit }' || true)"

if [[ ! "$workspace" =~ ^w[1-9][0-9]$ ]]; then
  workspace="$(tr -d '[:space:]' < "$state_file" 2>/dev/null || true)"
fi

if [[ ! "$workspace" =~ ^w[1-9][0-9]$ ]]; then
  workspace="w10"
fi

"$hud_run" >/dev/null 2>&1 || true

printf '%s\n' "$workspace" > "$state_file" 2>/dev/null || true
printf '%s %s.%s\n' "$workspace" "$(date +%s)" "$$" > "$show_file" 2>/dev/null || true
