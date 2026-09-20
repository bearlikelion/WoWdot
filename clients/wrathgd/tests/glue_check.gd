class_name GlueCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const STEP_TIMEOUT_MSEC: int = 120000
# The local AzerothCore stack answers on the shifted ports.
const REALMLIST: String = "127.0.0.1:3725"
const ACCOUNT: String = "wowgd"
const PASSWORD: String = "wowgd"
const CHARACTER: String = "Wrathglue"

var _failures: PackedStringArray = []
var _main: Main
var _glue: Glue
var _select: CharacterSelect
var _create: CharacterCreate
var _characters: Array = []
var _enumerations: int = 0
var _elapsed: int = 0


# Runs the real client against AzerothCore: log in, make a character, enter the world.
func _ready() -> void:
	_main = MAIN.instantiate()
	add_child(_main)
	_glue = _main.get_node("%Glue")
	_select = _glue.get_node("%CharacterSelect")
	_create = _glue.get_node("%CharacterCreate")
	WowClient.session.characters_received.connect(_on_characters_received)
	_run.call_deferred()


func _run() -> void:
	var login: LoginScreen = _glue.get_node("%AccountLogin")
	login.fill(REALMLIST, ACCOUNT, PASSWORD)
	await _frames(30)
	_capture("user://wotlk_login.png")
	# WOWDOT_MOTION samples the glue scene's loop, which runs for over a minute.
	if not OS.get_environment("WOWDOT_MOTION").is_empty():
		for second: int in [4, 20, 35, 50, 62]:
			await get_tree().create_timer(second - _elapsed).timeout
			_elapsed = second
			_capture("user://wotlk_login_%02d.png" % second)
	login.log_in()
	if not await _until(_select_ready, "the character screen shows"):
		return _finish()
	await _frames(30)
	_capture("user://wotlk_characters.png")
	if not _names().has(CHARACTER) and not await _make_character():
		return _finish()
	_select.select(_names().find(CHARACTER))
	_select.enter_world()
	if not await _until(func() -> bool: return _main.world != null, "the world scene appears"):
		return _finish()
	if not await _until(func() -> bool: return _main.world.player().active,
			"the player takes the world"):
		return _finish()
	var made: Dictionary = _character()
	print("%s, race %d class %d, in the world at %v" % [
		CHARACTER, made["race"], made["class"],
		WowCoords.from_godot(_main.world.player().global_position),
	])
	_check(WowClient.session.get_state() == WowSession.STATE_IN_WORLD,
			"the session reports being in the world")
	_finish()


func _make_character() -> bool:
	(_select.get_node("%CharSelectCreateCharacterButton") as BaseButton).pressed.emit()
	if not await _until(func() -> bool: return _create.visible, "the create screen opens"):
		return false
	(_create.get_node("%CharacterCreateNameEdit") as LineEdit).text = CHARACTER
	(_create.get_node("%CharCreateOkayButton") as BaseButton).pressed.emit()
	return await _until(func() -> bool: return _select_ready() and _names().has(CHARACTER),
			"%s is created" % CHARACTER)


func _select_ready() -> bool:
	return _select.visible and _enumerations > 0


func _on_characters_received(characters: Array) -> void:
	_characters = characters
	_enumerations += 1


func _character() -> Dictionary:
	for character: Dictionary in _characters:
		if character["name"] == CHARACTER:
			return character
	return {}


func _names() -> PackedStringArray:
	var names: PackedStringArray = []
	for character: Dictionary in _characters:
		names.append(character["name"])
	return names


func _until(condition: Callable, what: String) -> bool:
	var give_up: int = Time.get_ticks_msec() + STEP_TIMEOUT_MSEC
	while not condition.call():
		if WowClient.session.get_state() == WowSession.STATE_FAILED:
			_failures.append("%s (session failed)" % what)
			return false
		if Time.get_ticks_msec() > give_up:
			_failures.append(what)
			return false
		await get_tree().process_frame
	return true


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


# Written only when a window is up, since a headless viewport has no texture.
func _capture(path: String) -> void:
	var image: Image = get_viewport().get_texture().get_image() if get_viewport().get_texture() \
			else null
	if image != null:
		image.save_png(path)
		print("wrote ", ProjectSettings.globalize_path(path))


func _check(condition: bool, what: String) -> bool:
	if not condition:
		_failures.append(what)
	return condition


func _finish() -> void:
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("glue_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
