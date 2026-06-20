#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 row|col prev|next" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage

axis="$1"
direction="$2"

case "$axis" in
  row | col) ;;
  *) usage ;;
esac

case "$direction" in
  prev | next) ;;
  *) usage ;;
esac

rows=9
cols=9
aerospace_bin="${AEROSPACE_BIN:-aerospace}"
state_file="/tmp/aerospace-hud-focused-workspace"

current="$(tr -d '[:space:]' < "$state_file" 2>/dev/null || true)"
if [[ ! "$current" =~ ^w[1-9][0-9]$ && ! "$current" =~ ^p[1-9][0-9]?$ ]]; then
  current="$("$aerospace_bin" list-workspaces --focused | head -n 1 | tr -d '[:space:]')"
fi

row=1
col=0

if [[ "$current" =~ ^w([1-9])([0-9])$ ]]; then
  row="${BASH_REMATCH[1]}"
  col="${BASH_REMATCH[2]}"
elif [[ "$current" =~ ^p([1-9])$ ]]; then
  row="${BASH_REMATCH[1]}"
  col=0
elif [[ "$current" =~ ^p([1-9])([1-9])$ ]]; then
  row="${BASH_REMATCH[1]}"
  col="${BASH_REMATCH[2]}"
else
  printf '%s\n' w10 > "$state_file" 2>/dev/null || true
  "$aerospace_bin" workspace w10
  exit 0
fi

if [[ "$axis" == "row" ]]; then
  if [[ "$direction" == "next" ]]; then
    row=$((row == rows ? rows : row + 1))
  else
    row=$((row == 1 ? 1 : row - 1))
  fi
else
  if [[ "$direction" == "next" ]]; then
    col=$((col == cols ? cols : col + 1))
  else
    col=$((col == 0 ? 0 : col - 1))
  fi
fi

if [[ "$col" -eq 0 ]]; then
  target="w${row}0"
else
  target="w${row}${col}"
fi

printf '%s\n' "$target" > "$state_file" 2>/dev/null || true
"$aerospace_bin" workspace "$target"
