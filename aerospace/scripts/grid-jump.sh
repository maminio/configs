#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 w10..w99|q0..qN" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/grid-common.sh"
grid_valid_workspace "$1" || usage
grid_acquire_lock
grid_switch "$1"
