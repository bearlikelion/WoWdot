class_name GlueCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const STEP_TIMEOUT_MSEC: int = 60000
const REALMLIST: String = "127.0.0.1"
const ACCOUNT: String = "wowgd"
const PASSWORD: String = "wowgd"
# Created and deleted again, so the account ends as it started.
const THROWAWAY: String = "Glueckcheck"

var _failures: PackedStringArray = []
var _main: Main
var _glue: Glue
var _dialog: GlueDialog
var _select: CharacterSelect
var _create: CharacterCreate
var _characters: Array = []


# Walks the glue screens against the server: login, create, delete, enter world.
func _ready() -> void:
	_main = MAIN.instantiate()
	add_child(_main)
	_glue = _main.get_node("%Glue")
	_dialog = _glue.get_node("%GlueDialog")
	_select = _glue.get_node("%CharacterSelect")
	_create = _glue.get_node("%CharacterCreate")
	WowClient.session.characters_received.connect(
		func(characters: Array) -> void: _characters = characters
	)
	_run.call_deferred()


func _run() -> void:
	await _frames(30)
	_capture("user://glue_login.png")
	var login: LoginScreen = _glue.get_node("%AccountLogin")
	login.fill(REALMLIST, ACCOUNT, PASSWORD)
	login.log_in()
	if not await _until(_select_ready, "the character list shows"):
		return _finish()
	await _frames(30)
	_capture("user://glue_select.png")
	var character: String = _names()[0]

	if _names().has(THROWAWAY):
		await _delete(THROWAWAY)
	(_select.get_node("%CharSelectCreateCharacterButton") as BaseButton).pressed.emit()
	await _frames(30)
	_check(_create.visible, "Create New Character opens character creation")
	_capture("user://glue_create.png")
	(_create.get_node("%CharacterCreateNameEdit") as LineEdit).text = THROWAWAY
	(_create.get_node("%CharCreateOkayButton") as BaseButton).pressed.emit()
	if not await _until(func() -> bool: return _select_ready() and _names().has(THROWAWAY),
			"%s is created" % THROWAWAY):
		_capture("user://glue_create_failed.png")
		return _finish()
	_check(_selected_name() == THROWAWAY, "the new character is selected")
	await _frames(30)
	_capture("user://glue_created.png")
	await _delete(THROWAWAY)

	var realms: RealmList = _glue.get_node("%RealmList")
	(_select.get_node("%CharSelectChangeRealmButton") as BaseButton).pressed.emit()
	if not await _until(func() -> bool: return realms.visible, "Change Realm lists the realms"):
		return _finish()
	await _frames(10)
	_capture("user://glue_realms.png")
	(realms.get_node("%RealmListOkButton") as BaseButton).pressed.emit()
	if not await _until(_select_ready, "choosing the realm returns to the character list"):
		return _finish()

	_select.select(_names().find(character))
	_select.enter_world()
	var loading: LoadingScreen = _glue.get_node("%LoadingScreen")
	_check(loading.visible, "entering the world shows the loading screen")
	var fill: Control = loading.get_node("%LoadingBarFill")
	await _until(func() -> bool: return fill.visible or not _glue.visible, "the loading bar fills")
	_check(_glue.visible, "the loading bar shows progress before the world appears")
	_capture("user://glue_loading.png")
	if not await _until(func() -> bool: return not _glue.visible, "the world finishes loading"):
		return _finish()
	await _frames(30)
	_capture("user://glue_world.png")
	_check(_main.world.player().active, "the player is active once the loading screen goes")
	_finish()


func _delete(character_name: String) -> void:
	_select.select(_names().find(character_name))
	(_select.get_node("%CharacterSelectDeleteButton") as BaseButton).pressed.emit()
	var edit: LineEdit = _select.get_node("%CharacterDeleteEditBox")
	var confirm: BaseButton = _select.get_node("%CharacterDeleteButton1")
	await _frames(10)
	_capture("user://glue_delete.png")
	_check(confirm.disabled, "deleting waits for DELETE to be typed")
	edit.text = "delete"
	edit.text_changed.emit(edit.text)
	_check(not confirm.disabled, "typing DELETE enables the delete button")
	confirm.pressed.emit()
	await _until(func() -> bool: return _select_ready() and not _names().has(character_name),
			"%s is deleted" % character_name)


func _select_ready() -> bool:
	return _select.visible and not _dialog.visible and not _characters.is_empty()


func _names() -> PackedStringArray:
	var names: PackedStringArray = []
	for character: Dictionary in _characters:
		names.append(character["name"])
	return names


func _selected_name() -> String:
	return (_select.get_node("%CharSelectCharacterName") as Label).text


func _until(condition: Callable, what: String) -> bool:
	var give_up: int = Time.get_ticks_msec() + STEP_TIMEOUT_MSEC
	while not condition.call():
		var failed: bool = WowClient.session.get_state() == WowSession.STATE_FAILED
		if failed or Time.get_ticks_msec() > give_up:
			_failures.append(what)
			return false
		await get_tree().process_frame
	return true


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _capture(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)


func _finish() -> void:
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("glue_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
