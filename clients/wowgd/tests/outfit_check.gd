class_name OutfitCheck
extends Node

# A human warrior is created in a Worn Shortsword and a Worn Wooden Shield, over shirt and pants.
const HUMAN: int = 1
const WARRIOR: int = 1
const MAGE: int = 8
const MALE: int = 0
const SHORTSWORD_DISPLAY: int = 1542
const SHIELD_DISPLAY: int = 18730

var _failures: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var look: Dictionary = CharacterModels.starting_look({
		"race": HUMAN, "class": WARRIOR, "gender": MALE,
	})
	var weapons: Array = look["weapons"]
	_check(weapons[0].display == SHORTSWORD_DISPLAY, "the warrior holds a sword")
	_check(weapons[1].display == SHIELD_DISPLAY, "the warrior holds a shield")
	var equipment: PackedInt32Array = look["equipment"]
	_check(equipment[CharacterModels.EquipSlot.SHIRT] > 0, "the warrior wears a shirt")
	_check(equipment[CharacterModels.EquipSlot.LEGS] > 0, "the warrior wears trousers")
	_check(equipment[CharacterModels.EquipSlot.FEET] > 0, "the warrior wears boots")
	var mage: Dictionary = CharacterModels.starting_look({
		"race": HUMAN, "class": MAGE, "gender": MALE,
	})
	_check(
		(mage["weapons"] as Array)[0].display != weapons[0].display,
		"a mage is created in something else",
	)
	if _failures.is_empty():
		print("outfit_check: OK")
	else:
		for line: String in _failures:
			print("  ", line)
		print("outfit_check: FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)
