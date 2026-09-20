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
# How far above the deck to stand, and how far above the hull the ray starts.
const STAND: float = 0.2
const PROBE: float = 40.0
const BOARD_FRAMES: int = 240

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
		await _ride(node)
	await _teleport(HOME)
	_finish("")


# Dropped onto the deck, the player should travel with it while their place on it holds still.
func _ride(node: Node3D) -> void:
	var player: Player = _main.world.player()
	# A .go round trip cannot catch a hull doing 30 yards a second, so the deck is found by ray.
	var aboard: bool = false
	for attempt: int in BOARD_FRAMES:
		var deck: Vector3 = _deck_under(node)
		if deck != Vector3.INF:
			player.global_position = deck + Vector3(0.0, STAND, 0.0)
		await get_tree().physics_frame
		aboard = player.transport_guid() != 0
		if aboard:
			break
	_check(aboard, "standing on the deck names the transport")
	if not aboard:
		printerr("deck ray: ", _deck_under(node), " node at ", node.global_position)
		return
	var seat: Vector3 = player.transport_offset()
	var was: Vector3 = player.global_position
	await _frames(SAIL_FRAMES)
	var carried: float = was.distance_to(player.global_position)
	var drift: float = seat.distance_to(player.transport_offset())
	print("carried %.1f yards, seat drifted %.2f" % [carried, drift])
	_check(carried > 1.0, "and the deck carries them along with it")
	_check(drift < 2.0, "while their place on it stays put")
	_check(
		WowClient.session.get_state() == WowSession.STATE_IN_WORLD,
		"and the server takes the movement it is told",
	)


# The topmost surface of the transport itself, or INF when it carries no collision to stand on.
func _deck_under(node: Node3D) -> Vector3:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		node.global_position + Vector3(0.0, PROBE, 0.0),
		node.global_position - Vector3(0.0, PROBE, 0.0),
	)
	var hit: Dictionary = node.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not node.is_ancestor_of(hit["collider"]):
		return Vector3.INF
	return hit["position"]


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
