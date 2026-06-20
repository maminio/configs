#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_file="$script_dir/mouse-button-down.swift"
build_dir="$script_dir/.build"
binary="$build_dir/mouse-button-down"

if [[ ! -x "$binary" || "$source_file" -nt "$binary" ]]; then
  mkdir -p "$build_dir"
  swiftc -O -module-cache-path "$build_dir/module-cache" -o "$binary" "$source_file"
fi

exec "$binary"
