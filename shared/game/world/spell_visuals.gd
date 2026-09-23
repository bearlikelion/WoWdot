class_name SpellVisuals
extends RefCounted

# SpellVisual.dbc holds a kit per stage of a cast.
enum Kit { PRECAST, CAST, IMPACT }

const KIT_SHAKE_COLUMN: int = 14
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
var _displays: WowDBC
var _kit_cache: Dictionary[Vector3i, Array] = {}


func _init(archive: WowArchive) -> void:
	_spells = WowDBC.open(archive, "Spell")
	_visuals = WowDBC.open(archive, "SpellVisual")
	_kits = WowDBC.open(archive, "SpellVisualKit")
	_names = WowDBC.open(archive, "SpellVisualEffectName")
	_anims = WowDBC.open(archive, "AnimationData")
	_displays = WowDBC.open(archive, "ItemDisplayInfo")


# What a stage of the cast hangs on the unit, as {path, points} per filled slot.
func effects(spell_id: int, kit: Kit, weapon_display: int = 0) -> Array[Dictionary]:
	var key: Vector3i = Vector3i(spell_id, kit, weapon_display)
	if _kit_cache.has(key):
		return _kit_cache[key]
	var found: Array[Dictionary] = _row_effects(_kit_row(spell_id, kit, weapon_display))
	_kit_cache[key] = found
	return found


# The same for a SpellVisualKit id named outright, as SMSG_PLAY_SPELL_VISUAL does.
func kit_effects(kit_id: int) -> Array[Dictionary]:
	return _row_effects(_kits.find(kit_id))


# The clip the unit plays for a stage, such as ReadySpellDirected while a fireball is cast.
func animation(spell_id: int, kit: Kit, weapon_display: int = 0) -> String:
	var kit_row: int = _kit_row(spell_id, kit, weapon_display)
	if kit_row < 0:
		return ""
	var id: int = _kits.get_int(kit_row, ANIM_COLUMN)
	var anim_row: int = _anims.find(id) if id >= 0 else -1
	return _anims.get_string(anim_row, ANIM_NAME_COLUMN) if anim_row >= 0 else ""


func has_missile(spell_id: int, weapon_display: int = 0) -> bool:
	return _field(spell_id, "HasMissile", weapon_display) != 0 \
	and not missile(spell_id, weapon_display).is_empty()


func missile(spell_id: int, weapon_display: int = 0) -> String:
	return _model(_field(spell_id, "MissileModel", weapon_display))


# Yards a second the missile travels; a spell with no speed of its own lands at once.
func missile_speed(spell_id: int) -> float:
	var row: int = _spells.find(spell_id)
	return _spells.get_float(row, "Speed") if row >= 0 else 0.0


func loot_sparkle() -> String:
	return _model(LOOT_EFFECT)


# The SpellEffectCameraShakes group a kit jolts the camera with, or 0.
func shake_group(spell_id: int, kit: Kit, weapon_display: int = 0) -> int:
	var row: int = _kit_row(spell_id, kit, weapon_display)
	return _kits.get_uint(row, KIT_SHAKE_COLUMN) if row >= 0 else 0


func _row_effects(kit_row: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if kit_row >= 0:
		for slot: String in SLOT_POINTS:
			var path: String = _model(_kits.get_uint(kit_row, slot))
			if not path.is_empty():
				found.append({"path": path, "points": SLOT_POINTS[slot]})
	return found


func _kit_row(spell_id: int, kit: Kit, weapon_display: int) -> int:
	var kit_id: int = _field(spell_id, KIT_COLUMNS[kit], weapon_display)
	return _kits.find(kit_id) if kit_id != 0 else -1


# A ranged shot such as Auto Shot fills each empty field of its visual from the weapon's own.
func _field(spell_id: int, column: String, weapon_display: int) -> int:
	var row: int = _visual_row(spell_id)
	var value: int = _visuals.get_uint(row, column) if row >= 0 else 0
	if value != 0 or weapon_display == 0 or not WowAssets.spells.uses_ranged_slot(spell_id):
		return value
	var display_row: int = _displays.find(weapon_display)
	if display_row < 0:
		return 0
	var weapon_row: int = _visuals.find(_displays.get_uint(display_row, "SpellVisualID"))
	return _visuals.get_uint(weapon_row, column) if weapon_row >= 0 else 0


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
