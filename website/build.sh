#!/usr/bin/env bash
# Assembles the static site into _site/.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly OUT="${ROOT}/_site"

main() {
  local releases="https://github.com/${SITE_REPO:-bearlikelion/WoWGD}/releases/latest"

  rm -rf "$OUT"
  mkdir -p "$OUT"
  "${ROOT}/website/screenshots.sh"
  cp "${ROOT}"/website/*.{html,css,png,json} "$OUT"/
  cp -r "${ROOT}"/website/wowgd "${ROOT}"/website/wrathgd "${ROOT}"/website/benchmark "$OUT"/
  sed -i "s|{{RELEASES}}|${releases}|g" "${OUT}/index.html"
}

main "$@"
