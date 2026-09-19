class_name ZoningCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const ZONE_MSEC: int = 90000
# Kalimdor, the Deadmines instance, and Coldridge Valley to come home to.
const ORGRIMMAR: Vector3 = Vector3(1629.36, -4373.39, 31.2564)
const DEADMINES: Vector3 = Vector3(-16.4, -383.07, 61.78)
const HOME: Vector3 = Vector3(-6248.77, 317.339, 382.778)
const MAP_KALIMDOR: int = 1
const MAP_DEADMINES: int = 36
const MAP_AZEROTH: int = 0

var _failures: PackedStringArray = []
var _main: Main
var _entered: Array[int] = []
var _pending: Array[int] = []


# Zones to another continent, into an instance and back, watching the loading screen each time.
func _ready() -> void:
	_main = MAIN.instantiate()
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
	var session: WowSession = WowClient.session
	session.transfer_pending.connect(func(map_id: int) -> void: _pending.append(map_id))
	session.world_entered.connect(
		func(map_id: int, _position: Vector3, _orientation: float) -> void:
			_entered.append(map_id)
	)
	await _zone(ORGRIMMAR, MAP_KALIMDOR, "Kalimdor")
	await _zone(DEADMINES, MAP_DEADMINES, "Deadmines")
	await _zone(HOME, MAP_AZEROTH, "Azeroth")
	_check(session.get_state() == WowSession.STATE_IN_WORLD, "the server kept the session")
	_finish("")


func _zone(wow_position: Vector3, map_id: int, map_name: String) -> void:
	var world: World = _main.world
	var glue: Glue = _main.get_node("%Glue")
	_pending.clear()
	_entered.clear()
	WowClient.session.send_chat(WowSession.CHAT_SAY, ".go xyz %f %f %f %d" % [
		wow_position.x, wow_position.y, wow_position.z, map_id,
	])
	var pending_by: int = Time.get_ticks_msec() + ZONE_MSEC
	while _pending.is_empty() and Time.get_ticks_msec() < pending_by:
		await get_tree().process_frame
	_check(_pending.has(map_id), "%s announces the transfer" % map_name)
	_check(glue.visible, "the loading screen covers the world while zoning")
	var entered_by: int = Time.get_ticks_msec() + ZONE_MSEC
	while _entered.is_empty() and Time.get_ticks_msec() < entered_by:
		await get_tree().process_frame
	_check(_entered.has(map_id), "%s is entered" % map_name)
	var loaded_by: int = Time.get_ticks_msec() + ZONE_MSEC
	while glue.visible and Time.get_ticks_msec() < loaded_by:
		await get_tree().process_frame
	_check(not glue.visible, "the loading screen closes once %s has streamed in" % map_name)
	var walking_by: int = Time.get_ticks_msec() + ZONE_MSEC
	while not world.player().active and Time.get_ticks_msec() < walking_by:
		await get_tree().process_frame
	_check(world.player().active, "the player walks on %s" % map_name)
	var entities: Entities = world.get_node("Entities")
	var strays: int = 0
	for guid: int in entities.guids():
		if not WowClient.session.has_object(guid):
			strays += 1
	_check(strays == 0, "the old map's objects are gone (%d left)" % strays)
	print(map_name, ": ", WowClient.session.get_object_guids().size(), " objects")


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)


func _finish(fatal: String) -> void:
	if not fatal.is_empty():
		_failures.append(fatal)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("zoning_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
