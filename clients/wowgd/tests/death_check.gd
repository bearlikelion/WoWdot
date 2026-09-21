class_name DeathCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 20000
# The corpse reclaim delay is up to a minute after a death that counts.
const RECLAIM_MSEC: int = 70000
const PLAYER_FLAG_GHOST: int = 0x10
# Made and deleted by death_check.sh: a fresh character has the shortest corpse reclaim delay.
const CHARACTER: String = "Grimka"

var _failures: PackedStringArray = []
var _main: Main


# Dies, releases the spirit, runs back to the corpse and resurrects there.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = "127.0.0.1"
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	_main.auto_character = CHARACTER
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var ready_at: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _main.world == null or not _main.world.player().active:
		if Time.get_ticks_msec() > ready_at:
			return _finish("never reached the world")
		await get_tree().process_frame
	await _frames(60)
	var session: WowSession = WowClient.session
	var me: int = session.get_player_guid()
	_main.world.select(me)
	# An earlier run may have left the character dead.
	if _ghost(me) or session.get_field(me, "UNIT_FIELD_HEALTH") == 0:
		session.send_chat(WowSession.CHAT_SAY, ".revive")
		if not await _until(func() -> bool: return not _ghost(me) \
		and session.get_field(me, "UNIT_FIELD_HEALTH") > 0):
			return _finish("could not revive the character before the check")
	var grave: Vector3 = WowCoords.from_godot(_main.world.player().global_position)
	session.send_chat(WowSession.CHAT_SAY, ".die")
	if not await _until(func() -> bool: return session.get_field(me, "UNIT_FIELD_HEALTH") == 0):
		return _finish("the player never died")
	var popup: StaticPopup = _popup()
	_check(popup != null and popup.visible, "death offers the release popup")
	print("death popup: ", _popup_text())
	_accept()
	if not await _until(func() -> bool: return _ghost(me)):
		return _finish("releasing the spirit never made a ghost")
	_check(true, "releasing the spirit works")
	var located: bool = await _until(
		func() -> bool: return _main.world._death.corpse_map >= 0, RECLAIM_MSEC
	)
	_check(located, "the corpse query answers where the body lies")
	if located:
		var minimap: MinimapView = _main.world.hud().find_child("Minimap", true, false)
		_check(minimap.get("_corpse_map") >= 0, "the minimap knows the corpse")
		var map_frame: Control = _main.world.hud().find_child("WorldMapFrame", true, false)
		map_frame.show()
		await _frames(30)
		var corpses: int = 0
		for marker: Node in map_frame.find_children("*", "WorldMapMarker", true, false):
			corpses += 1 if (marker as WorldMapMarker).kind == WorldMapMarker.Kind.CORPSE else 0
		_check(corpses == 1, "the world map shows one corpse marker (%d)" % corpses)
		_capture("user://death_corpse_map.png")
		map_frame.hide()
		await _frames(10)

	session.send_chat(
		WowSession.CHAT_SAY, ".go xyz %f %f %f" % [grave.x, grave.y, grave.z]
	)
	await _frames(120)
	var offered: bool = await _until(
		func() -> bool: return _popup().visible, RECLAIM_MSEC
	)
	if not offered:
		var death: Death = _main.world._death
		print("no corpse popup: map ", death.corpse_map, " guid ", death.corpse_guid(),
			" wait ", death.reclaim_wait_msec(), " ghost ", _ghost(me), " health ",
			session.get_field(me, "UNIT_FIELD_HEALTH"), " away ",
			WowCoords.to_godot(death.corpse_position).distance_to(
				_main.world.player().global_position))
	_check(offered, "standing on the corpse offers to resurrect")
	if offered:
		print("corpse popup: ", _popup_text())
		_accept()
		var alive: bool = await _until(
			func() -> bool: return not _ghost(me) \
			and session.get_field(me, "UNIT_FIELD_HEALTH") > 0
		)
		_check(alive, "resurrecting at the corpse brings the player back")
	_check(session.get_state() == WowSession.STATE_IN_WORLD, "the server kept the session")
	_finish("")


func _ghost(guid: int) -> bool:
	return (WowClient.session.get_field(guid, "PLAYER_FLAGS") & PLAYER_FLAG_GHOST) != 0


func _popup() -> StaticPopup:
	return _main.world.hud().find_child("StaticPopup1", true, false)


func _popup_text() -> String:
	var label: Label = _popup().find_child("StaticPopup1Text", true, false)
	return label.text if label else ""


func _accept() -> void:
	var button: BaseButton = _popup().find_child("StaticPopup1Button1", true, false)
	button.pressed.emit()


func _capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))


func _until(condition: Callable, timeout_msec: int = STEP_MSEC) -> bool:
	var until: int = Time.get_ticks_msec() + timeout_msec
	while not condition.call() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	return condition.call()


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
	print("death_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
