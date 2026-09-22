#!/usr/bin/env bash
# Lists the screenshots in wowgd/ and wrathgd/ as screenshots.json, which the carousel reads.
# A folder's order.txt names the files that go first, one per line; the rest follow alphabetically.
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

list() {
  local dir="$1" first=1 f
  local -a ordered=()
  printf '"%s": [' "$dir"
  if [ -f "$dir/order.txt" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] && [ -e "$dir/$f" ] && ordered+=("$dir/$f")
    done < "$dir/order.txt"
  fi
  for f in "$dir"/*.png "$dir"/*.jpg "$dir"/*.webp; do
    [ -e "$f" ] || continue
    case " ${ordered[*]-} " in *" $f "*) continue ;; esac
    ordered+=("$f")
  done
  for f in "${ordered[@]-}"; do
    [ -n "$f" ] || continue
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
