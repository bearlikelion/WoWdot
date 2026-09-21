class_name AreaTriggerCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 20000
# The Deadmines entrance, which the server answers by teleporting the player into map 36.
const PORTAL: int = 78
const DEADMINES: int = 36
const PORTAL_LEVEL: int = 20
const HOME: Vector3 = Vector3(-6248.77, 317.339, 382.778)
# Where to land beside the portal, and how many frames to take walking into it.
const APPROACH: float = 14.0
const WALK_FRAMES: int = 240

var _failures: PackedStringArray = []
var _main: Main
var _map_id: int = 0


# Walking into an area trigger is the client's job to report, and instance portals hang on it.
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
	var session: WowSession = WowClient.session
	session.world_entered.connect(
		func(map_id: int, _at: Vector3, _facing: float) -> void: _map_id = map_id
	)
	session.send_chat(WowSession.CHAT_SAY, ".character level %d" % PORTAL_LEVEL)
	await _frames(120)

	var triggers: AreaTriggers = _main.world.get_node("AreaTriggers")
	var fired: PackedInt32Array = []
	triggers.entered.connect(func(trigger_id: int) -> void: fired.append(trigger_id))
	var at: Vector3 = _trigger_position(PORTAL)
	_check(at != Vector3.INF, "the portal has a place in AreaTrigger.dbc")
	if at == Vector3.INF:
		return _finish("no trigger to walk into")
	print("trigger %d sits at %s" % [PORTAL, at])

	_map_id = 0
	# Arriving inside a portal must not fire it, so the check walks in from outside its radius.
	await _teleport(at + Vector3(APPROACH, 0.0, 0.0), 0)
	_check(fired.is_empty(), "landing beside it fires nothing")
	var player: Player = _main.world.player()
	for step: int in WALK_FRAMES:
		if not fired.is_empty():
			break
		player.global_position = player.global_position.lerp(
			WowCoords.to_godot(at), 1.0 / float(WALK_FRAMES - step)
		)
		await get_tree().physics_frame
	var reported: bool = await _until(func() -> bool: return fired.has(PORTAL))
	_check(reported, "standing in it reports the trigger to the server")
	var moved: bool = await _until(func() -> bool: return _map_id == DEADMINES)
	print("fired %s, landed on map %d" % [fired, _map_id])
	_check(moved, "and the server answers by opening the instance")
	_check(
		session.get_state() == WowSession.STATE_IN_WORLD,
		"with the session still in the world afterwards",
	)
	await _teleport(HOME, 0)
	_check(fired.count(PORTAL) <= 2, "the trigger is reported on entry, not every frame")
	_finish("")


func _trigger_position(trigger_id: int) -> Vector3:
	var dbc: WowDBC = WowDBC.open(WowAssets.archive, "AreaTrigger")
	var row: int = dbc.find(trigger_id) if dbc else -1
	if row < 0:
		return Vector3.INF
	return Vector3(
		dbc.get_float(row, "X"), dbc.get_float(row, "Y"), dbc.get_float(row, "Z")
	)


func _teleport(wow_position: Vector3, map_id: int) -> void:
	WowClient.session.send_chat(
		WowSession.CHAT_SAY,
		".go xyz %f %f %f %d" % [wow_position.x, wow_position.y, wow_position.z, map_id],
	)
	await _frames(30)
	await _until(func() -> bool: return _main.world.player().active, TIMEOUT_MSEC)
	await _frames(60)


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
	print("area_trigger_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
