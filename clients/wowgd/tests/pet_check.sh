#!/bin/sh
# Makes a throwaway warlock, summons its imp through the check, and deletes the character again.
cd "$(dirname "$0")/.." || exit 1
warlock="--create=Warlik --race=1 --class=9"
godot --headless --path . --script tests/throwaway_character.gd -- $warlock || exit 1
godot --headless --path . tests/pet_check.tscn
status=$?
godot --headless --path . --script tests/throwaway_character.gd -- --delete=Warlik
exit $status
