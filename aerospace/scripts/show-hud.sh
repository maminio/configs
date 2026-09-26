#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/grid-common.sh"
show_file="/tmp/aerospace-mission-control-toggle"
hud_run="/Users/aminmoradi/workspace/configs/aerospace/hud/run.sh"

# Launching/rebuilding can take time. Only read focus afterwards, under the same
# lock as navigation, so the toggle cannot restore an obsolete focus hint.
"$hud_run" >/dev/null 2>&1 || true
grid_acquire_lock

workspace="$("$aerospace_bin" list-workspaces --focused 2>/dev/null | awk '/^w[1-9][0-9]$|^q(0|[1-9][0-9]*)$/ { print; exit }' || true)"

if ! grid_valid_workspace "$workspace"; then
  workspace="$(tr -d '[:space:]' < "$state_file" 2>/dev/null || true)"
fi

if ! grid_valid_workspace "$workspace"; then
  workspace="w10"
fi

printf '%s\n' "$workspace" > "$state_file" 2>/dev/null || true
printf '%s %s.%s\n' "$workspace" "$(date +%s)" "$$" > "$show_file" 2>/dev/null || true
