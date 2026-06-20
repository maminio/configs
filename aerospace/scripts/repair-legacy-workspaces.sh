#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${AEROSPACE_BIN:-}" ]]; then
  if [[ -x /opt/homebrew/bin/aerospace ]]; then
    AEROSPACE_BIN=/opt/homebrew/bin/aerospace
  elif [[ -x /usr/local/bin/aerospace ]]; then
    AEROSPACE_BIN=/usr/local/bin/aerospace
  fi
fi

aerospace_bin="${AEROSPACE_BIN:-aerospace}"
state_file="/tmp/aerospace-hud-focused-workspace"
attempts="${AEROSPACE_REPAIR_LEGACY_ATTEMPTS:-20}"
delay="${AEROSPACE_REPAIR_LEGACY_DELAY:-0.4}"

move_legacy_workspace() {
  local legacy="$1"
  local target="w${legacy}0"
  local windows

  windows="$("$aerospace_bin" list-windows --workspace "$legacy" --format '%{window-id}' 2>/dev/null || true)"

  while IFS= read -r window_id; do
    [[ "$window_id" =~ ^[0-9]+$ ]] || continue
    "$aerospace_bin" move-node-to-workspace --window-id "$window_id" "$target" >/dev/null 2>&1 || true
  done <<< "$windows"
}

for ((attempt = 1; attempt <= attempts; attempt++)); do
  moved_any=0

  for legacy in 1 2 3 4 5 6 7 8 9; do
    before="$("$aerospace_bin" list-windows --workspace "$legacy" --count 2>/dev/null || true)"
    [[ "$before" =~ ^[0-9]+$ && "$before" -gt 0 ]] || continue

    move_legacy_workspace "$legacy"
    moved_any=1
  done

  if [[ "$moved_any" -eq 1 ]]; then
    printf '%s\n' w10 > "$state_file" 2>/dev/null || true
    "$aerospace_bin" workspace w10 >/dev/null 2>&1 || true
  fi

  sleep "$delay"
done
