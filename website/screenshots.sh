#!/usr/bin/env bash
# Lists the screenshots in wowgd/ and wrathgd/ as screenshots.json, which the carousel reads.
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

list() {
  local dir="$1" first=1
  printf '"%s": [' "$dir"
  for f in "$dir"/*.png "$dir"/*.jpg "$dir"/*.webp; do
    [ -e "$f" ] || continue
    [ "$first" = 1 ] || printf ', '
    printf '"%s"' "$f"
    first=0
  done
  printf ']'
}

{
  printf '{'
  list wowgd
  printf ', '
  list wrathgd
  printf '}\n'
} > screenshots.json
