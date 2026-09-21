class_name LevelCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 15000
# FactionTemplate rows: 1 is the Human player faction and 14 the Monster one every mob starts from.
const PLAYER_TEMPLATE: int = 1
const MONSTER_TEMPLATE: int = 14

var _failures: PackedStringArray = []
var _main: Main
var _levels: Array[int] = []
var _health: int = 0
var _mana: int = 0
var _stats: PackedInt32Array = []


# A GM level up: the chime, the notice, the gains in the chat and the nameplate colours around it.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = "127.0.0.1"
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	WowClient.session.leveled_up.connect(_on_leveled_up)
	_run.call_deferred()


func _run() -> void:
	var ready_at: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _main.world == null or not _main.world.player().active:
		if Time.get_ticks_msec() > ready_at:
			return _finish("never reached the world")
		await get_tree().process_frame
	await _frames(60)
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	var was: int = session.get_field(guid, "UNIT_FIELD_LEVEL")
	session.send_chat(WowSession.CHAT_SAY, ".levelup 1")
	if not _check(await _until(func() -> bool: return not _levels.is_empty()),
			"the server sends the level up"):
		return _finish("")
	_check(_levels[0] == was + 1, "the level up names level %d, not %d" % [was + 1, _levels[0]])
	var glow: Node3D = _main.world.player().model().find_child("LevelUp", true, false) as Node3D
	_check(glow != null, "the level up glow plays on the player")
	if glow != null:
		_check(not glow.find_children("*", "MeshInstance3D", true, false).is_empty(),
				"the glow carries its rings, which rest invisible until they fade in")
	_check(_health > 0, "the level up carries the health gained")
	_check(_stats.size() == 5, "the level up carries five stat gains")
	print("level %d: %d health, %d mana, stats %s" % [_levels[0], _health, _mana, _stats])
	_check(await _until(func() -> bool:
		return session.get_field(guid, "UNIT_FIELD_LEVEL") == _levels[0]
	), "the player's level field follows")
	_check(WowAssets.audio.has_sound("LEVELUP"), "the level up chime is in SoundEntries")
	var notice: String = WowStrings.get_text("LEVEL_UP") % _levels[0]
	_check(_noticed(notice), "the level up shows over the screen")
	_names_by_reaction()
	_finish("")


# UIErrorsFrame keeps a label per line for as long as it shows it.
func _noticed(text: String) -> bool:
	var errors: WowMessageFrame = _main.world.find_child("UIErrorsFrame", true, false)
	if errors == null:
		return false
	for line: Node in errors.get_children():
		if (line as Label).text == text:
			return true
	return false


# FACTION_BAR_COLORS: a hostile unit's nameplate reads red, a friendly one green.
func _names_by_reaction() -> void:
	var session: WowSession = WowClient.session
	var entities: Entities = _main.world.find_child("Entities", true, false)
	var seen: Dictionary[String, int] = {}
	for guid: int in session.get_object_guids():
		if session.get_object_type(guid) != Entities.ObjectType.UNIT:
			continue
		var plate: Label3D = entities.nameplate(guid)
		if plate == null:
			continue
		var reaction: UnitReaction.Reaction = UnitReaction.between(
			session, session.get_player_guid(), guid
		)
		var wanted: Color = UnitReaction.COLORS[reaction]
		seen[UnitReaction.Reaction.keys()[UnitReaction.Reaction.values().find(reaction)]] = 1
		_check(plate.modulate.is_equal_approx(wanted),
				"%s reads in its reaction colour" % session.get_object_name(guid))
	print("nameplate reactions seen: %s" % ", ".join(seen.keys()))
	_check(not seen.is_empty(), "some unit around the player carries a nameplate")
	# Nothing hostile has to be standing nearby for the red case to be worth checking.
	_check(UnitReaction.between_templates(PLAYER_TEMPLATE, MONSTER_TEMPLATE)
			== UnitReaction.Reaction.HOSTILE, "a monster faction reads hostile to a player")
	_check(UnitReaction.between_templates(PLAYER_TEMPLATE, PLAYER_TEMPLATE)
			== UnitReaction.Reaction.FRIENDLY, "a player's own faction reads friendly")
	# The mob the yellow names were first seen on.
	var defias: PackedInt32Array = _templates_of("Defias Brotherhood")
	_check(not defias.is_empty(), "FactionTemplate carries the Defias Brotherhood")
	for template: int in defias:
		_check(UnitReaction.between_templates(PLAYER_TEMPLATE, template)
				== UnitReaction.Reaction.HOSTILE, "Defias template %d reads hostile" % template)
	print("Defias Brotherhood templates: %s" % defias)


func _templates_of(faction_name: String) -> PackedInt32Array:
	var factions: WowDBC = WowDBC.open(WowAssets.archive, "Faction")
	var templates: WowDBC = WowDBC.open(WowAssets.archive, "FactionTemplate")
	var found: PackedInt32Array = []
	for row: int in factions.row_count():
		if factions.get_string(row, "Name") != faction_name:
			continue
		var faction: int = factions.get_uint(row, "ID")
		for template: int in templates.row_count():
			if templates.get_uint(template, "Faction") == faction:
				found.append(templates.get_uint(template, "ID"))
	return found


func _on_leveled_up(level: int, health: int, mana: int, stats: PackedInt32Array) -> void:
	_levels.append(level)
	_health = health
	_mana = mana
	_stats = stats


func _until(condition: Callable, timeout_msec: int = STEP_MSEC) -> bool:
	var until: int = Time.get_ticks_msec() + timeout_msec
	while not condition.call() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	return condition.call()


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _check(condition: bool, what: String) -> bool:
	if not condition:
		_failures.append(what)
	return condition


func _finish(fatal: String) -> void:
	if not fatal.is_empty():
		_failures.append(fatal)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("level_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
