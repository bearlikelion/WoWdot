class_name VisualCheck
extends Node

# Fireball and Frostbolt throw a missile; Frost Armor and Healing Touch only dress the unit.
const MISSILE_SPELLS: PackedInt32Array = [133, 116]
const KIT_SPELLS: PackedInt32Array = [133, 116, 168, 5185]

var _failures: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var visuals: SpellVisuals = WowAssets.spell_visuals
	var spells: SpellInfo = WowAssets.spells
	for spell: int in KIT_SPELLS:
		var stages: int = 0
		for kit: SpellVisuals.Kit in [
			SpellVisuals.Kit.PRECAST, SpellVisuals.Kit.CAST, SpellVisuals.Kit.IMPACT,
		]:
			var effects: Array[Dictionary] = visuals.effects(spell, kit)
			stages += 1 if not effects.is_empty() else 0
			for effect: Dictionary in effects:
				_check(
					WowAssets.archive.has(effect["path"]),
					"%s has %s" % [spells.spell_name(spell), effect["path"]],
				)
		_check(stages >= 2, "%s dresses the caster at least twice over" % spells.spell_name(spell))
	for spell: int in MISSILE_SPELLS:
		_check(visuals.has_missile(spell), "%s throws a missile" % spells.spell_name(spell))
		_check(visuals.missile_speed(spell) > 0.0, "%s has a speed" % spells.spell_name(spell))
	_check(not visuals.has_missile(168), "Frost Armor throws nothing")
	var sparkle: String = visuals.loot_sparkle()
	_check(not sparkle.is_empty(), "loot has its sparkle: " + sparkle)
	var model: Node3D = WowAssets.loader.load_m2(visuals.missile(133))
	_check(model != null, "the fireball missile loads")
	if model:
		var emitters: int = model.find_children("Particles*", "GPUParticles3D", true, false).size()
		_check(emitters > 0, "the fireball missile emits (%d)" % emitters)
		model.queue_free()
	if _failures.is_empty():
		print("visual_check: OK")
	else:
		for line: String in _failures:
			print("  ", line)
		print("visual_check: FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)
