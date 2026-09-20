#!/bin/sh
# Makes the partner's character on the second test account, runs the check, and deletes it again.
cd "$(dirname "$0")/.." || exit 1
partner="--account=wowgd2 --password=wowgd2"
godot --headless --path . --script tests/throwaway_character.gd -- --create=Dolgrim $partner || exit 1
godot --path . --resolution 1280x960 tests/raid_check.tscn
status=$?
godot --headless --path . --script tests/throwaway_character.gd -- --delete=Dolgrim $partner
exit $status
