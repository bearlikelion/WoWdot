#!/bin/sh
# Makes the throwaway character, runs the check on it, and deletes it again.
cd "$(dirname "$0")/.." || exit 1
godot --headless --path . --script tests/throwaway_character.gd -- --create=Bolgrin || exit 1
godot --path . --resolution 1280x960 tests/npc_services_check.tscn
status=$?
godot --headless --path . --script tests/throwaway_character.gd -- --delete=Bolgrin
exit $status
