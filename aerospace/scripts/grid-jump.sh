#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 w10..w99" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage

target="$1"
[[ "$target" =~ ^w[1-9][0-9]$ ]] || usage

aerospace_bin="${AEROSPACE_BIN:-aerospace}"
state_file="/tmp/aerospace-hud-focused-workspace"

printf '%s\n' "$target" > "$state_file" 2>/dev/null || true
"$aerospace_bin" workspace "$target"
