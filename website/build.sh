#!/usr/bin/env bash
# Assembles the site into _site/ with a GDDocs API page per client.
# Needs the Linux debug extension built; GODOT picks the editor binary.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly OUT="${ROOT}/_site"
readonly GODOT="${GODOT:-godot}"
readonly LIBRARY="shared/wowdot/bin/libwowdot.linux.template_debug.x86_64.so"
readonly CLIENTS=(wowgd)

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

main() {
  command -v "$GODOT" >/dev/null || die "godot not found, set GODOT"
  [[ -f "${ROOT}/${LIBRARY}" ]] \
    || die "missing ${LIBRARY}, run scons target=template_debug in extension/"

  # SITE_REPO is the public GitHub repo holding the releases; local builds get a dead link.
  local releases="${SITE_REPO:+https://github.com/${SITE_REPO}/releases/latest}"

  rm -rf "$OUT"
  mkdir -p "$OUT"
  cp "${ROOT}"/website/*.{html,css,png} "$OUT"/
  sed -i "s|{{RELEASES}}|${releases:-#}|g" "${OUT}/index.html"

  local client project
  for client in "${CLIENTS[@]}"; do
    project="${ROOT}/clients/${client}"
    timeout 900 "$GODOT" --headless --path "$project" --import
    "$GODOT" --headless --path "$project" \
      --script res://addons/gddocs/gddocs_cli.gd
    mkdir -p "${OUT}/api/${client}"
    cp "${project}/docs/api/index.html" "${OUT}/api/${client}/"
  done
}

main "$@"
