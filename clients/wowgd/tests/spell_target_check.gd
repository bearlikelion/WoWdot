class_name SpellTargetCheck
extends Node

# Frost Armor, Blink and Evocation land on the caster; the rest keep whatever is targeted.
const SELF_CAST: PackedInt32Array = [168, 1953, 12051]
const NEEDS_TARGET: PackedInt32Array = [133, 2050, 1459]

var _failures: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var spells: SpellInfo = WowAssets.spells
	for spell: int in SELF_CAST:
		_check(spells.targets_caster(spell), "%s casts on the caster" % spells.spell_name(spell))
	for spell: int in NEEDS_TARGET:
		_check(
			not spells.targets_caster(spell),
			"%s keeps its target" % spells.spell_name(spell),
		)
	if _failures.is_empty():
		print("spell_target_check: OK")
	else:
		for line: String in _failures:
			print("  ", line)
		print("spell_target_check: FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)
