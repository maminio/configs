#!/usr/bin/env bash
# Shared grid addressing. Quick-action spaces are q0, q1, ... above row 1.
# Source this file; it does not invoke AeroSpace by itself.
grid_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
aerospace_bin="${AEROSPACE_BIN:-aerospace}"
state_file="${AEROSPACE_FOCUSED_STATE_FILE:-/tmp/aerospace-hud-focused-workspace}"
quick_spaces_file="${AEROSPACE_QUICK_SPACES_FILE:-$grid_script_dir/../hud/.quick-spaces-count}"

# AeroSpace launches shortcuts independently. Share this native PID lock with
# the HUD so computing a target and validating/moving a window is one operation.
# shlock reclaims locks left by dead processes without unlinking a live lock.
grid_acquire_lock() {
  [[ "${grid_lock_held:-0}" == 1 ]] && return 0
  grid_lock_file="${quick_spaces_file}.lock"
  local attempt
  for ((attempt = 0; attempt < 500; attempt++)); do
    if /usr/bin/shlock -p "$$" -f "$grid_lock_file"; then
      grid_lock_held=1
      trap 'rm -f -- "$grid_lock_file"' EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM
      return 0
    fi
    sleep 0.01
  done
  echo "Workspace navigation is busy or its state directory is not writable; please try again." >&2
  return 1
}

grid_valid_workspace() {
  [[ "$1" =~ ^w[1-9][0-9]$ || "$1" =~ ^q(0|[1-9][0-9]*)$ ]]
}

grid_current_workspace() {
  local current=""
  if [[ -r "$state_file" ]]; then
    current="$(tr -d '[:space:]' < "$state_file")"
  fi
  if ! grid_valid_workspace "$current" && [[ ! "$current" =~ ^p[1-9][0-9]?$ ]]; then
    current="$("$aerospace_bin" list-workspaces --focused | awk '/^w[1-9][0-9]$|^q(0|[1-9][0-9]*)$|^p[1-9][0-9]?$/ { print; exit }')"
  fi
  printf '%s\n' "$current"
}

grid_quick_count() {
  local count=1 saved=""
  if [[ -r "$quick_spaces_file" ]]; then
    saved="$(tr -d '[:space:]' < "$quick_spaces_file")"
    # Bound arithmetic input to avoid signed shell-integer overflow.
    if [[ "$saved" =~ ^[1-9][0-9]*$ && ${#saved} -lt 18 ]]; then count="$saved"; fi
  fi
  if [[ "${1:-}" =~ ^q(0|[1-9][0-9]*)$ ]]; then
    local index="${1#q}"
    if [[ ${#index} -lt 18 ]] && (( index >= count )); then count=$((index + 1)); fi
  fi
  printf '%s\n' "$count"
}

grid_target() {
  local current="$1" axis="$2" direction="$3" row=1 col=0 count
  if [[ "$current" =~ ^q(0|[1-9][0-9]*)$ ]]; then
    row=0
    col="${BASH_REMATCH[1]}"
    [[ ${#col} -lt 18 ]] || return 1
  elif [[ "$current" =~ ^w([1-9])([0-9])$ ]]; then
    row="${BASH_REMATCH[1]}"; col="${BASH_REMATCH[2]}"
  elif [[ "$current" =~ ^p([1-9])([1-9])?$ ]]; then
    row="${BASH_REMATCH[1]}"; col="${BASH_REMATCH[2]:-0}"
  else
    printf 'w10\n'
    return
  fi
  if [[ "$axis" == row ]]; then
    if [[ "$direction" == next ]]; then
      row=$((row == 9 ? 9 : row + 1))
    else
      row=$((row == 0 ? 0 : row - 1))
    fi
    if (( row == 0 )); then
      count="$(grid_quick_count "$current")"
      col=$((col >= count ? count - 1 : col))
    else
      col=$((col > 9 ? 9 : col))
    fi
  else
    local last=9
    if (( row == 0 )); then
      count="$(grid_quick_count "$current")"
      last=$((count - 1))
    fi
    if [[ "$direction" == next ]]; then col=$((col >= last ? last : col + 1));
    else col=$((col == 0 ? 0 : col - 1)); fi
  fi
  if (( row == 0 )); then printf 'q%s\n' "$col";
  else printf 'w%s%s\n' "$row" "$col"; fi
}

grid_switch() {
  "$aerospace_bin" workspace "$1" || return
  printf '%s\n' "$1" > "$state_file" 2>/dev/null || true
}

grid_move_focused_window() {
  grid_acquire_lock || return 1
  local target="$1" window_id inventory
  if [[ "$target" == q* ]]; then
    # Identify the actual focused window, then validate against fresh inventory.
    window_id="$("$aerospace_bin" list-windows --focused --format '%{window-id}' | awk '/^[0-9]+$/ { print; exit }')" || return 1
    [[ "$window_id" =~ ^[0-9]+$ ]] || return 1
    inventory="$("$aerospace_bin" list-windows --all --format $'%{workspace}\t%{window-id}\t%{app-name}\t%{app-bundle-id}')" || return 1
    if ! printf '%s\n' "$inventory" | awk -F '\t' -v source="$window_id" -v target="$target" '
      $2 == source && NF >= 4 { sourceApp = $3; sourceBundle = $4; found = 1 }
      $1 == target && $2 != source { apps[++n] = $3; bundles[n] = $4; if (NF < 4) invalid = 1 }
      END {
        if (!found || sourceApp == "" || invalid) exit 1
        for (i = 1; i <= n; i++) {
          if (sourceBundle != "" && bundles[i] != "") {
            if (sourceBundle != bundles[i]) exit 1
          } else if (sourceApp != apps[i]) exit 1
        }
      }'; then
      printf '\aQuick-action spaces hold one application. Choose an empty space or one with the same app.\n' >&2
      return 1
    fi
    "$aerospace_bin" move-node-to-workspace --window-id "$window_id" --focus-follows-window "$target" || return
  else
    "$aerospace_bin" move-node-to-workspace --focus-follows-window "$target" || return
  fi
  printf '%s\n' "$target" > "$state_file" 2>/dev/null || true
}
