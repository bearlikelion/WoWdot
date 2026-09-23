class_name SpellInfo
extends RefCounted

enum RangeCheck { NO_RANGE, IN_RANGE, OUT_OF_RANGE }

const QUESTION_MARK_ICON: String = "Interface\\Icons\\INV_Misc_QuestionMark"
const GENERAL_TAB_ICON: String = "Interface\\Icons\\INV_Misc_Book_09"
const EFFECT_TRADE_SKILL: int = 47
const SKILL_CATEGORY_CLASS: int = 7
const SPELL_ATTR_DO_NOT_DISPLAY: int = 0x80
const RANGE_SELF: int = 1
const RANGE_FLAG_MELEE: int = 0x1
# Melee reach is both units' combat reach plus this, and never under MELEE_RANGE.
const MELEE_LEEWAY: float = 4.0 / 3.0
const MELEE_RANGE: float = 5.0

var _spells: WowDBC
var _icons: WowDBC
var _cast_times: WowDBC
var _ranges: WowDBC
var _icon_textures: Dictionary[String, WowTexture] = {}
var _skill_lines: WowDBC
# Each spell's class skill line, such as Arms, from SkillLineAbility.
var _class_lines: Dictionary[int, int] = {}
# Each spell's skill line of any kind, professions included.
var _all_lines: Dictionary[int, int] = {}


func _init(archive: WowArchive) -> void:
	_spells = WowDBC.open(archive, "Spell")
	_icons = WowDBC.open(archive, "SpellIcon")
	_cast_times = WowDBC.open(archive, "SpellCastTimes")
	_ranges = WowDBC.open(archive, "SpellRange")


func spell_name(spell_id: int) -> String:
	return _string(spell_id, "Name")


func rank(spell_id: int) -> String:
	return _string(spell_id, "Rank")


func description(spell_id: int) -> String:
	return _string(spell_id, "Description")


func icon(spell_id: int) -> Texture2D:
	var row: int = _spells.find(spell_id)
	var path: String = QUESTION_MARK_ICON
	if row >= 0:
		var icon_row: int = _icons.find(_spells.get_uint(row, "IconID"))
		if icon_row >= 0:
			path = _icons.get_string(icon_row, "Path")
	return icon_texture(path)


# A SpellIcon.dbc row's path, without the extension, or empty.
func icon_path(icon_id: int) -> String:
	var icon_row: int = _icons.find(icon_id)
	return _icons.get_string(icon_row, "Path") if icon_row >= 0 else ""


func icon_texture(path: String) -> WowTexture:
	if not _icon_textures.has(path):
		var texture: WowTexture = WowTexture.new()
		texture.file = path + ".blp"
		_icon_textures[path] = texture
	return _icon_textures[path]


# IsActionInRange, measured between the units' edges like the server's range check.
func range_check(spell_id: int, caster: int, target: int) -> RangeCheck:
	var session: WowSession = WowClient.session
	var row: int = _spells.find(spell_id)
	var range_row: int = _ranges.find(_spells.get_uint(row, "RangeIndex")) if row >= 0 else -1
	if target == 0 or not session.has_object(target) or range_row < 0 \
	or _ranges.get_uint(range_row, "ID") == RANGE_SELF:
		return RangeCheck.NO_RANGE
	var distance: float = session.get_object_position(caster).distance_to(
		session.get_object_position(target)
	)
	var reach: float = session.get_field_float(caster, "UNIT_FIELD_COMBATREACH") \
			+ session.get_field_float(target, "UNIT_FIELD_COMBATREACH")
	var in_range: bool = false
	if _ranges.get_uint(range_row, "Flags") & RANGE_FLAG_MELEE:
		in_range = distance <= maxf(reach + MELEE_LEEWAY, MELEE_RANGE)
	else:
		distance -= reach
		in_range = distance >= _ranges.get_float(range_row, "MinRange") \
				and distance <= _ranges.get_float(range_row, "MaxRange")
	return RangeCheck.IN_RANGE if in_range else RangeCheck.OUT_OF_RANGE


func cast_time_msec(spell_id: int) -> int:
	var row: int = _spells.find(spell_id)
	if row < 0:
		return 0
	var cast_row: int = _cast_times.find(_spells.get_uint(row, "CastingTimeIndex"))
	return _cast_times.get_uint(cast_row, "Base") if cast_row >= 0 else 0


func global_cooldown_msec(spell_id: int) -> int:
	return _uint(spell_id, "StartRecoveryTime")


func global_cooldown_category(spell_id: int) -> int:
	return _uint(spell_id, "StartRecoveryCategory")


func dispel_type(spell_id: int) -> int:
	return _uint(spell_id, "DispelType")


# GetTrackingTexture: Find Herbs, Track Beasts and the like apply a tracking aura.
func is_tracking(spell_id: int) -> bool:
	const TRACKING_AURAS: Array[int] = [44, 45]
	for effect: int in 3:
		if _uint(spell_id, "EffectAura%d" % effect) in TRACKING_AURAS:
			return true
	return false


func is_passive(spell_id: int) -> bool:
	const SPELL_ATTR_PASSIVE: int = 0x40
	return _uint(spell_id, "Attributes") & SPELL_ATTR_PASSIVE != 0


# Auto Shot, Shoot and Throw: casting them draws the ranged weapon.
func uses_ranged_slot(spell_id: int) -> bool:
	const SPELL_ATTR_USES_RANGED_SLOT: int = 0x2
	return _uint(spell_id, "Attributes") & SPELL_ATTR_USES_RANGED_SLOT != 0


# A buff like Frost Armor lands on the caster whatever is targeted, so it is cast with no target.
func targets_caster(spell_id: int) -> bool:
	const EFFECT_TARGET_COLUMN: int = 82
	const EFFECT_COUNT: int = 3
	const TARGET_SELF: int = 1
	var row: int = _spells.find(spell_id)
	if row < 0:
		return false
	var self_cast: bool = false
	for effect: int in EFFECT_COUNT:
		var target: int = _spells.get_uint(row, EFFECT_TARGET_COLUMN + effect)
		if target == TARGET_SELF:
			self_cast = true
		elif target != 0:
			return false
	return self_cast


# Spells the stock spellbook lists; weapon and armor skills, languages and internal spells hide.
func is_displayed(spell_id: int) -> bool:
	return _uint(spell_id, "Attributes") & SPELL_ATTR_DO_NOT_DISPLAY == 0


# GetSpellTabInfo as {name, icon, spells}: General, then class skill lines in talent tree order.
func book_tabs(known: PackedInt32Array) -> Array[Dictionary]:
	if _skill_lines == null:
		_load_skill_lines()
	var general: Array[int] = []
	var by_line: Dictionary[int, Array] = {}
	for spell: int in known:
		if not is_displayed(spell):
			continue
		var line: int = _class_lines.get(spell, 0)
		if line == 0:
			general.append(spell)
		else:
			if not by_line.has(line):
				by_line[line] = []
			by_line[line].append(spell)
	var tabs: Array[Dictionary] = [{
		"name": WowStrings.get_text("GENERAL"),
		"icon": icon_texture(GENERAL_TAB_ICON),
		"spells": _by_name_and_rank(general),
	}]
	var lines: Array[int] = []
	lines.assign(by_line.keys())
	lines.sort_custom(func(a: int, b: int) -> bool: return _line_name(a) < _line_name(b))
	for line: int in lines:
		var spells: Array[int] = []
		spells.assign(by_line[line])
		var icon_id: int = _skill_lines.get_uint(_skill_lines.find(line), "SpellIconID")
		var icon_row: int = _icons.find(icon_id)
		tabs.append({
			"name": _line_name(line),
			"icon": icon_texture(
				_icons.get_string(icon_row, "Path") if icon_row >= 0 else QUESTION_MARK_ICON
			),
			"spells": _by_name_and_rank(spells),
		})
	return tabs


func _load_skill_lines() -> void:
	_skill_lines = WowDBC.open(WowAssets.archive, "SkillLine")
	var abilities: WowDBC = WowDBC.open(WowAssets.archive, "SkillLineAbility")
	for row: int in abilities.row_count():
		var line: int = abilities.get_uint(row, "SkillLineID")
		var line_row: int = _skill_lines.find(line)
		var spell: int = abilities.get_uint(row, "SpellID")
		_all_lines[spell] = line
		if line_row >= 0 and _skill_lines.get_uint(line_row, "Category") == SKILL_CATEGORY_CLASS:
			_class_lines[spell] = line


# The spell a trainer's teaching spell gives, which is what the trainer lists.
func taught_spell(spell_id: int) -> int:
	var taught: int = _uint(spell_id, "EffectTriggerSpell0")
	return taught if taught else spell_id


# Enchants, poisons and sharpening stones are aimed at an item, not a unit.
func targets_item(spell_id: int) -> bool:
	return _uint(spell_id, "Targets") & ItemTargeting.TARGET_FLAG_ITEM != 0


# A profession's own spell only opens its window, through SPELL_EFFECT_TRADE_SKILL.
func opens_trade_skill(spell_id: int) -> bool:
	for i: int in 3:
		if _uint(spell_id, "Effect%d" % i) == EFFECT_TRADE_SKILL:
			return true
	return false


func skill_line(spell_id: int) -> int:
	if _skill_lines == null:
		_load_skill_lines()
	return _all_lines.get(spell_id, 0)


func skill_line_name(line: int) -> String:
	if _skill_lines == null:
		_load_skill_lines()
	var row: int = _skill_lines.find(line)
	return _skill_lines.get_string(row, "Name") if row >= 0 else ""


func _line_name(line: int) -> String:
	return _skill_lines.get_string(_skill_lines.find(line), "Name")


func _by_name_and_rank(spells: Array[int]) -> Array[int]:
	var sorted: Array[int] = spells.duplicate()
	sorted.sort_custom(func(a: int, b: int) -> bool:
		if spell_name(a) != spell_name(b):
			return spell_name(a) < spell_name(b)
		return rank(a).to_int() < rank(b).to_int()
	)
	return sorted


func _string(spell_id: int, column: String) -> String:
	var row: int = _spells.find(spell_id)
	return _spells.get_string(row, column) if row >= 0 else ""


func _uint(spell_id: int, column: String) -> int:
	var row: int = _spells.find(spell_id)
	return _spells.get_uint(row, column) if row >= 0 else 0
