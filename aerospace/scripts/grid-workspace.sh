#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 row|col prev|next" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage
case "$1" in row | col) ;; *) usage ;; esac
case "$2" in prev | next) ;; *) usage ;; esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/grid-common.sh"
grid_acquire_lock
current="$(grid_current_workspace)"
target="$(grid_target "$current" "$1" "$2")"
grid_switch "$target"
