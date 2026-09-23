class_name RangedVisualCheck
extends Node

const AUTO_SHOT: int = 75
const BOW_DISPLAY: int = 8106
const GUN_DISPLAY: int = 6606
# Rough Arrow, the ammo SMSG_SPELL_GO names as a bow shot's missile.
const ARROW_DISPLAY: int = 5996


func _ready() -> void:
	var visuals: SpellVisuals = WowAssets.spell_visuals
	var failures: PackedStringArray = []
	var expected: Dictionary[int, PackedStringArray] = {
		BOW_DISPLAY: ["LoadBow", "AttackBow"],
		GUN_DISPLAY: ["LoadRifle", "AttackRifle"],
	}
	for display: int in expected:
		var precast: String = visuals.animation(AUTO_SHOT, SpellVisuals.Kit.PRECAST, display)
		var cast: String = visuals.animation(AUTO_SHOT, SpellVisuals.Kit.CAST, display)
		if [precast, cast] != Array(expected[display]):
			failures.append("display %d played %s, %s" % [display, precast, cast])
	if not visuals.animation(AUTO_SHOT, SpellVisuals.Kit.CAST).is_empty():
		failures.append("Auto Shot drew a clip with no weapon")
	if WowAssets.characters.item_models.load_ammo(ARROW_DISPLAY) == null:
		failures.append("the arrow model did not load")
	for failure: String in failures:
		printerr(failure)
	print("ranged visual check: ", "FAIL" if failures else "ok")
	get_tree().quit(1 if failures else 0)
