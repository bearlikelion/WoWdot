class_name SpellVisuals
extends RefCounted

# SpellVisual.dbc holds a kit per stage of a cast.
enum Kit { PRECAST, CAST, IMPACT }

const KIT_COLUMNS: Dictionary[Kit, String] = {
	Kit.PRECAST: "PrecastKit", Kit.CAST: "CastKit", Kit.IMPACT: "ImpactKit",
}
# Each SpellVisualKit slot and the M2 attachment points it hangs on, best first.
const SLOT_POINTS: Dictionary[String, Array] = {
	"HeadEffect": [20, 11],
	"ChestEffect": [34, 15, 19],
	"BaseEffect": [19],
	"LeftHandEffect": [21, 2],
	"RightHandEffect": [22, 1],
	"BreathEffect": [17, 20],
	"SpecialEffect0": [23, 19],
	"SpecialEffect1": [24, 19],
	"SpecialEffect2": [25, 19],
}
# SpellVisualEffectName calls this one "HARDCODED Loot Art"; the client hangs it on loot.
const LOOT_EFFECT: int = 14
# SpellVisualKit names the clip the unit plays, and AnimationData holds its name.
const ANIM_COLUMN: int = 2
const ANIM_NAME_COLUMN: int = 1

var _spells: WowDBC
var _visuals: WowDBC
var _kits: WowDBC
var _names: WowDBC
var _anims: WowDBC
var _kit_cache: Dictionary[int, Array] = {}


func _init(archive: WowArchive) -> void:
	_spells = WowDBC.open(archive, "Spell")
	_visuals = WowDBC.open(archive, "SpellVisual")
	_kits = WowDBC.open(archive, "SpellVisualKit")
	_names = WowDBC.open(archive, "SpellVisualEffectName")
	_anims = WowDBC.open(archive, "AnimationData")


# What a stage of the cast hangs on the unit, as {path, points} per filled slot.
func effects(spell_id: int, kit: Kit) -> Array[Dictionary]:
	var key: int = spell_id * KIT_COLUMNS.size() + int(kit)
	if _kit_cache.has(key):
		return _kit_cache[key]
	var found: Array[Dictionary] = []
	var kit_row: int = _kit_row(spell_id, kit)
	if kit_row >= 0:
		for slot: String in SLOT_POINTS:
			var path: String = _model(_kits.get_uint(kit_row, slot))
			if not path.is_empty():
				found.append({"path": path, "points": SLOT_POINTS[slot]})
	_kit_cache[key] = found
	return found


# The clip the unit plays for a stage, such as ReadySpellDirected while a fireball is cast.
func animation(spell_id: int, kit: Kit) -> String:
	var kit_row: int = _kit_row(spell_id, kit)
	if kit_row < 0:
		return ""
	var id: int = _kits.get_int(kit_row, ANIM_COLUMN)
	var anim_row: int = _anims.find(id) if id >= 0 else -1
	return _anims.get_string(anim_row, ANIM_NAME_COLUMN) if anim_row >= 0 else ""


func has_missile(spell_id: int) -> bool:
	var row: int = _visual_row(spell_id)
	return row >= 0 and _visuals.get_uint(row, "HasMissile") != 0 and not missile(spell_id).is_empty()


func missile(spell_id: int) -> String:
	var row: int = _visual_row(spell_id)
	return _model(_visuals.get_uint(row, "MissileModel")) if row >= 0 else ""


# Yards a second the missile travels; a spell with no speed of its own lands at once.
func missile_speed(spell_id: int) -> float:
	var row: int = _spells.find(spell_id)
	return _spells.get_float(row, "Speed") if row >= 0 else 0.0


func loot_sparkle() -> String:
	return _model(LOOT_EFFECT)


func _kit_row(spell_id: int, kit: Kit) -> int:
	var row: int = _visual_row(spell_id)
	return _kits.find(_visuals.get_uint(row, KIT_COLUMNS[kit])) if row >= 0 else -1


func _visual_row(spell_id: int) -> int:
	var row: int = _spells.find(spell_id)
	return _visuals.find(_spells.get_uint(row, "SpellVisualID")) if row >= 0 else -1


# The DBCs name the .mdx the effect shipped as; the archive holds it as .m2.
func _model(effect_id: int) -> String:
	if effect_id <= 0:
		return ""
	var row: int = _names.find(effect_id)
	if row < 0:
		return ""
	var path: String = _names.get_string(row, "FilePath").get_basename() + ".m2"
	return path if WowAssets.archive.has(path) else ""
