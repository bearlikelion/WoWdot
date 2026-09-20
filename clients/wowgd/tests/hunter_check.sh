#!/bin/sh
# Makes a throwaway hunter, tames and stables a pet through the check, then deletes the character.
cd "$(dirname "$0")/.." || exit 1
hunter="--create=Huntik --race=3 --class=3"
godot --headless --path . --script tests/throwaway_character.gd -- $hunter || exit 1
sleep 3
godot --headless --path . tests/hunter_check.tscn
status=$?
godot --headless --path . --script tests/throwaway_character.gd -- --delete=Huntik
exit $status
