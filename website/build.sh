#!/usr/bin/env bash
# Assembles the static site into _site/.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly OUT="${ROOT}/_site"

main() {
  # SITE_REPO is the public GitHub repo holding the releases; local builds get a dead link.
  local releases="${SITE_REPO:+https://github.com/${SITE_REPO}/releases/latest}"

  rm -rf "$OUT"
  mkdir -p "$OUT"
  cp "${ROOT}"/website/*.{html,css,png} "$OUT"/
  sed -i "s|{{RELEASES}}|${releases:-#}|g" "${OUT}/index.html"
}

main "$@"
