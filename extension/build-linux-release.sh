#!/usr/bin/env bash
# Builds the Linux release library in the same buildroot SDK image as the Godot export template (glibc 2.28 floor).
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
podman run --rm -v "$PWD:/src" -w /src/extension localhost/godot-linux:4.7-f43 \
  bash -c 'export PATH="$GODOT_SDK_LINUX_X86_64/bin:$PATH" && scons -j"$(nproc)" target=template_release LINKFLAGS="-static-libstdc++ -static-libgcc"'
objdump -T shared/wowdot/bin/libwowdot.linux.template_release.x86_64.so | grep -o 'GLIBC_[0-9.]*' | sort -V | uniq | tail -1
