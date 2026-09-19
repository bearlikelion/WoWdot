#!/bin/sh
# Runs the check on a fresh character, whose corpse reclaim delay is the shortest, then removes it.
cd "$(dirname "$0")/.." || exit 1
godot --headless --path . --script tests/throwaway_character.gd -- --create=Grimka || exit 1
godot --headless --path . tests/death_check.tscn
status=$?
godot --headless --path . --script tests/throwaway_character.gd -- --delete=Grimka
exit $status
