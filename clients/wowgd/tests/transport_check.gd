class_name TransportCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 20000
# The Grom'Gol to Undercity zeppelin, whose taxi path stays on the eastern kingdoms.
const ZEPPELIN_ENTRY: int = 176495
const TOWER: Vector3 = Vector3(-12326.9, 1460.6, 30.0)
const HOME: Vector3 = Vector3(-6248.77, 317.339, 382.778)
# How long to watch it sail before asking whether it moved.
const SAIL_FRAMES: int = 300

var _failures: PackedStringArray = []
var _main: Main


# A transport sails its own taxi path, since the server stops sending its position after the first.
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
	var entities: Entities = _main.world.get_node("Entities")
	var transports: Transports = _main.world.get_node("Transports")
	await _teleport(TOWER)
	var zeppelin: int = 0
	for attempt: int in 8:
		zeppelin = _object_with_entry(ZEPPELIN_ENTRY)
		if zeppelin != 0:
			break
		await _frames(300)
	if zeppelin == 0:
		await _teleport(HOME)
		return _finish("no zeppelin at the Grom'Gol tower")

	var info: Dictionary = session.get_game_object_info(ZEPPELIN_ENTRY)
	print("zeppelin info: ", info)
	var fields: PackedInt32Array = info.get("data", PackedInt32Array())
	_check(fields.size() >= 2, "the game object query carries its type data")
	if fields.size() >= 2:
		_check(fields[Transports.Data.PATH] > 0, "whose first field is the taxi path it sails")
	var routed: bool = await _until(func() -> bool: return transports._routes.has(zeppelin))
	_check(routed, "and the client builds a route from it")
	if not routed:
		await _teleport(HOME)
		return _finish("no route to sail")
	print("route: %d legs over %.1f seconds" % [
		(transports._routes[zeppelin]["lengths"] as PackedFloat32Array).size(),
		transports._routes[zeppelin]["period"],
	])

	var node: Node3D = entities.unit_node(zeppelin)
	_check(node != null, "the zeppelin has a model of its own")
	if node:
		var was: Vector3 = node.global_position
		await _frames(SAIL_FRAMES)
		var moved: float = was.distance_to(node.global_position)
		print("it moved %.1f yards in %d frames" % [moved, SAIL_FRAMES])
		_check(moved > 1.0, "and sails along the path")
	await _teleport(HOME)
	_finish("")


func _object_with_entry(entry: int) -> int:
	var session: WowSession = WowClient.session
	for guid: int in session.get_object_guids():
		if session.get_field(guid, "OBJECT_FIELD_ENTRY") == entry:
			return guid
	return 0


func _teleport(wow_position: Vector3) -> void:
	WowClient.session.send_chat(
		WowSession.CHAT_SAY, ".go xyz %f %f %f" % [wow_position.x, wow_position.y, wow_position.z]
	)
	await _frames(30)
	await _until(func() -> bool: return _main.world.player().active, TIMEOUT_MSEC)
	await _frames(120)


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
	print("transport_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
