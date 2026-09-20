#!/bin/sh
# Runs the check on a fresh mage, who knows Fireball from level one, then removes him.
cd "$(dirname "$0")/.." || exit 1
godot --headless --path . --script tests/throwaway_character.gd -- \
	--create=Wiztest --race=7 --class=8 || exit 1
godot --path . tests/effect_check.tscn
status=$?
godot --headless --path . --script tests/throwaway_character.gd -- --delete=Wiztest
exit $status
