class_name GearCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const FLAG_WAIT_MSEC: int = 5000
const NAMEPLATE: StringName = &"Nameplate"

var _failures: PackedStringArray = []
var _main: Main


# Show Helm, Show Cloak and Show Own Name: the server keeps the first two, this client the third.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = "127.0.0.1"
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var ready_at: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _main.world == null or not _main.world.player().active:
		if Time.get_ticks_msec() > ready_at:
			return _finish("never reached the world")
		await get_tree().process_frame
	await _frames(60)
	var settings: InterfaceSettings = WowAssets.interface
	_check(
		settings.is_on(&"show_helm") == (_hidden(CharacterModels.PLAYER_FLAG_HIDE_HELM) == 0),
		"the box starts on what the character's own flag says",
	)
	await _toggle(&"show_helm", CharacterModels.PLAYER_FLAG_HIDE_HELM, "helm")
	await _toggle(&"show_cloak", CharacterModels.PLAYER_FLAG_HIDE_CLOAK, "cloak")
	await _check_own_name()
	_finish("")


# Turning the option off has to reach the server, hide the gear and come back on again.
func _toggle(option: StringName, flag: int, what: String) -> void:
	var worn: int = _head_or_cape(flag)
	print("%s worn: %d" % [what, worn])
	WowAssets.interface.set_on(option, false)
	await _wait_for_flag(flag, true)
	_check(_hidden(flag) == flag, "unticking show %s sets the server's flag" % what)
	await _frames(10)
	_check(_head_or_cape(flag) == 0, "and the %s stops being worn" % what)
	WowAssets.interface.set_on(option, true)
	await _wait_for_flag(flag, false)
	_check(_hidden(flag) == 0, "ticking it back clears the flag")
	await _frames(10)
	_check(_head_or_cape(flag) == worn, "and the %s comes back" % what)


func _check_own_name() -> void:
	var plate: Label3D = _main.world.player().model().get_node_or_null(NodePath(NAMEPLATE))
	if plate == null:
		_failures.append("the player's model carries a nameplate")
		return
	var settings: InterfaceSettings = WowAssets.interface
	_check(plate.text.begins_with(WowClient.session.get_object_name(
		WowClient.session.get_player_guid()
	)), "it carries the player's own name (%s)" % plate.text)
	settings.set_on(&"show_own_name", true)
	await _frames(2)
	_check(plate.visible, "Show Own Name shows it")
	settings.set_on(&"show_own_name", false)
	await _frames(2)
	_check(not plate.visible, "and unticking hides it again")


func _hidden(flag: int) -> int:
	var session: WowSession = WowClient.session
	return session.get_field(session.get_player_guid(), "PLAYER_FLAGS") & flag


# The head display when asked about the helm flag, the cape display when asked about the cloak.
func _head_or_cape(flag: int) -> int:
	var session: WowSession = WowClient.session
	var look: Dictionary = CharacterModels.player_look(session, session.get_player_guid())
	if flag == CharacterModels.PLAYER_FLAG_HIDE_HELM:
		return (look["equipment"] as PackedInt32Array)[CharacterModels.EquipSlot.HEAD]
	return look["cape"]


func _wait_for_flag(flag: int, set_now: bool) -> void:
	var until: int = Time.get_ticks_msec() + FLAG_WAIT_MSEC
	while (_hidden(flag) != 0) != set_now and Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)


func _finish(fatal: String) -> void:
	if not fatal.is_empty():
		_failures.append(fatal)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("gear_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
