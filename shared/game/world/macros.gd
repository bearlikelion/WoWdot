class_name Macros
extends RefCounted

signal changed
signal cast_requested(spell_id: int)
signal line_requested(text: String)

const SETTINGS_PATH: String = "user://macros.cfg"
const MAX_MACROS: int = 18
const MAX_BODY: int = 255
const CAST_COMMANDS: PackedStringArray = ["/cast", "/spell"]

var _session: WowSession
# Slot to {"name", "icon", "body"}; the slot is the id an action button stores.
var _macros: Dictionary[int, Dictionary] = {}
var _character: String = ""


func _init(session: WowSession) -> void:
	_session = session
	session.world_entered.connect(func(_map: int, _at: Vector3, _facing: float) -> void: _load())
	_load()


# Ids 1 to 18 belong to the account; 19 to 36 are the character's, filed under its guid.
func _load() -> void:
	_macros.clear()
	# The name is not known yet at world entry, and the guid always is.
	_character = str(_session.get_player_guid())
	var saved: ConfigFile = ConfigFile.new()
	if saved.load(SETTINGS_PATH) != OK:
		return
	for section: String in saved.get_sections():
		var owner: String = section.get_slice("/", 0) if section.contains("/") else ""
		if not owner.is_empty() and owner != _character:
			continue
		_macros[section.get_slice("/", section.get_slice_count("/") - 1).to_int()] = {
			"name": saved.get_value(section, "name", ""),
			"icon": saved.get_value(section, "icon", ""),
			"body": saved.get_value(section, "body", ""),
		}
	changed.emit()


func ids(of_character: bool) -> Array[int]:
	var found: Array[int] = []
	for id: int in _macros:
		if (id > MAX_MACROS) == of_character:
			found.append(id)
	found.sort()
	return found


func info(id: int) -> Dictionary:
	return _macros.get(id, {})


# The new macro's id, or 0 when all eighteen slots are taken.
func create(macro_name: String, icon: String, of_character: bool) -> int:
	var first: int = MAX_MACROS + 1 if of_character else 1
	for id: int in range(first, first + MAX_MACROS):
		if not _macros.has(id):
			_macros[id] = {"name": macro_name, "icon": icon, "body": ""}
			_save()
			return id
	return 0


func edit(id: int, macro_name: String, icon: String) -> void:
	if _macros.has(id):
		_macros[id]["name"] = macro_name
		_macros[id]["icon"] = icon
		_save()


func set_body(id: int, body: String) -> void:
	if _macros.has(id) and _macros[id]["body"] != body:
		_macros[id]["body"] = body.left(MAX_BODY)
		_save()


func delete(id: int) -> void:
	if _macros.erase(id):
		_save()


# Each line runs as if typed into chat, except a cast, which names a spell the character knows.
func run(id: int) -> void:
	for line: String in String(info(id).get("body", "")).split("\n", false):
		var text: String = line.strip_edges()
		var command: String = text.get_slice(" ", 0).to_lower()
		if command in CAST_COMMANDS:
			var spell_id: int = _known_spell(text.substr(command.length()).strip_edges())
			if spell_id != 0:
				cast_requested.emit(spell_id)
		elif not text.is_empty():
			line_requested.emit(text)


# "Name(Rank 2)" asks for that rank; a bare name takes the highest rank known.
func _known_spell(wanted: String) -> int:
	var rank: String = ""
	var open: int = wanted.find("(")
	if open >= 0:
		rank = wanted.substr(open + 1).trim_suffix(")").strip_edges().to_lower()
		wanted = wanted.left(open).strip_edges()
	var best: int = 0
	for spell_id: int in _session.get_known_spells():
		if WowAssets.spells.spell_name(spell_id).to_lower() != wanted.to_lower():
			continue
		if rank.is_empty():
			# ponytail: ranks are taken to rise with the spell id, which holds for stock class spells.
			best = maxi(best, spell_id)
		elif WowAssets.spells.rank(spell_id).to_lower() == rank:
			return spell_id
	return best


func _save() -> void:
	var saved: ConfigFile = ConfigFile.new()
	saved.load(SETTINGS_PATH)
	# Other characters' sections stay as they are; this one's and the account's are rewritten.
	for section: String in saved.get_sections():
		if not section.contains("/") or section.begins_with(_character + "/"):
			saved.erase_section(section)
	for id: int in _macros:
		var section: String = str(id) if id <= MAX_MACROS else "%s/%d" % [_character, id]
		for key: String in _macros[id]:
			saved.set_value(section, key, _macros[id][key])
	saved.save(SETTINGS_PATH)
	changed.emit()
