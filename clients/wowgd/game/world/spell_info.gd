class_name SpellInfo
extends RefCounted

const QUESTION_MARK_ICON: String = "Interface\\Icons\\INV_Misc_QuestionMark"

var _spells: WowDBC
var _icons: WowDBC
var _cast_times: WowDBC
var _icon_textures: Dictionary[String, WowTexture] = {}


func _init(archive: WowArchive) -> void:
	_spells = WowDBC.open(archive, "Spell")
	_icons = WowDBC.open(archive, "SpellIcon")
	_cast_times = WowDBC.open(archive, "SpellCastTimes")


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


func icon_texture(path: String) -> WowTexture:
	if not _icon_textures.has(path):
		var texture: WowTexture = WowTexture.new()
		texture.file = path + ".blp"
		_icon_textures[path] = texture
	return _icon_textures[path]


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


func is_passive(spell_id: int) -> bool:
	const SPELL_ATTR_PASSIVE: int = 0x40
	return _uint(spell_id, "Attributes") & SPELL_ATTR_PASSIVE != 0


func _string(spell_id: int, column: String) -> String:
	var row: int = _spells.find(spell_id)
	return _spells.get_string(row, column) if row >= 0 else ""


func _uint(spell_id: int, column: String) -> int:
	var row: int = _spells.find(spell_id)
	return _spells.get_uint(row, column) if row >= 0 else 0
