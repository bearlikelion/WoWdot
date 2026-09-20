#!/usr/bin/env bash
# Assembles the static site into _site/.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly OUT="${ROOT}/_site"

main() {
  rm -rf "$OUT"
  mkdir -p "$OUT"
  cp "${ROOT}"/website/*.{html,css,png} "$OUT"/
}

main "$@"
