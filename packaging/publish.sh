#!/usr/bin/env bash
# Attaches the local WoWGD export to a GitHub release; run it after exporting both presets.
# Releases are built locally because the presets encrypt the pck, and only export templates
# compiled with the key can load one.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly OUT="${ROOT}/export/wowgd"
readonly REPO="${SITE_REPO:-bearlikelion/wowdot-site}"

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

main() {
  local tag="${1:-}"
  [[ -n "$tag" ]] || die "usage: packaging/publish.sh <tag>"
  command -v gh >/dev/null || die "gh not found"
  [[ -f "${OUT}/linux/WoWGD.x86_64" ]] || die "missing the Linux export"
  [[ -f "${OUT}/windows/WoWGD.exe" ]] || die "missing the Windows export"

  mkdir -p "${OUT}/dist"
  rm -f "${OUT}"/dist/*.zip
  local platform
  for platform in linux windows; do
    cp "${ROOT}/packaging/wowgd/README.txt" "${ROOT}/LICENSE" "${ROOT}/NOTICE.md" \
      "${OUT}/${platform}/"
    # Named rather than globbed: the export dirs also hold symlinks into a real WoW install.
    (cd "${OUT}/${platform}" \
      && zip -q "../dist/WoWGD-${platform}.zip" WoWGD.* libwowdot.* README.txt LICENSE NOTICE.md)
  done

  gh release create "$tag" --repo "$REPO" --title "WoWGD $tag" \
    --notes "Unzip into your own World of Warcraft 1.12.1 (build 5875) folder. See README.txt in the zip." \
    || true
  gh release upload "$tag" --repo "$REPO" --clobber "${OUT}"/dist/*.zip
}

main "$@"
