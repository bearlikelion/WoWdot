class_name TransportCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 20000
# The Grom'Gol to Undercity zeppelin, whose taxi path stays on the eastern kingdoms.
const ZEPPELIN_ENTRY: int = 176495
const TOWER: Vector3 = Vector3(-12326.9, 1460.6, 30.0)
const HOME: Vector3 = Vector3(-6248.77, 317.339, 382.778)
# The upper Thunder Bluff mesa lift, on Kalimdor, and a spot on the rise beside it.
const LIFT_ENTRY: int = 4170
const BLUFF: Vector3 = Vector3(-1294.0, 188.0, 131.0)
# Proudmoore's Treasure, the Menethil to Theramore ferry, whose taxi path changes continent.
const FERRY_PATH: int = 292
# How long to watch it sail before asking whether it moved.
const SAIL_FRAMES: int = 300
# Placed a hair inside the deck: a lift descending away from the feet never reports a contact.
const STAND: float = -0.05
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
	await _teleport(TOWER, 0)
	var zeppelin: int = 0
	for attempt: int in 8:
		zeppelin = _object_with_entry(ZEPPELIN_ENTRY)
		if zeppelin != 0:
			break
		await _frames(300)
	if zeppelin == 0:
		await _teleport(HOME, 0)
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
		await _teleport(HOME, 0)
		return _finish("no route to sail")
	print("route: %d legs over %.1f seconds" % [
		(transports._routes[zeppelin]["lengths"] as PackedFloat32Array).size(),
		transports._routes[zeppelin]["period"],
	])

	var node: Node3D = entities.unit_node(zeppelin)
	_check(node != null, "the zeppelin has a model of its own")
	if node:
		await _ride(node)
	await _teleport(HOME, 0)
	await _check_lift()
	await _teleport(HOME, 0)
	_check_crossing()
	_finish("")


# A ferry between continents keeps its far legs, which still cost the route the time they take.
func _check_crossing() -> void:
	var route: Dictionary = TaxiNodes.path_route(FERRY_PATH)
	var maps: PackedInt32Array = route["maps"]
	var seen: Dictionary[int, bool] = {}
	for map: int in maps:
		seen[map] = true
	print("the ferry path: %d nodes over maps %s" % [maps.size(), seen.keys()])
	_check(seen.size() > 1, "the ferry path keeps the legs on both continents")
	_check(maps.size() > 2, "as one polyline rather than the half this map can see")


# A lift is animated wholly by the client, so riding one must not claim a transport on the wire.
func _check_lift() -> void:
	var transports: Transports = _main.world.get_node("Transports")
	var entities: Entities = _main.world.get_node("Entities")
	var player: Player = _main.world.player()
	await _teleport(BLUFF, 1)
	var lift: int = 0
	for attempt: int in 8:
		lift = _object_with_entry(LIFT_ENTRY)
		if lift != 0 and transports._lifts.has(lift):
			break
		await _frames(300)
	_check(lift != 0 and transports._lifts.has(lift), "the mesa lift builds an animation loop")
	if lift == 0 or not transports._lifts.has(lift):
		return
	var node: Node3D = entities.unit_node(lift)
	_check(
		not node.find_children("*", "StaticBody3D", true, false).is_empty(),
		"and the lift model carries collision to stand on",
	)
	print("lift period %.1fs over %d frames" % [
		transports._lifts[lift]["period"],
		(transports._lifts[lift]["times"] as PackedFloat32Array).size(),
	])
	var low: float = node.global_position.y
	var high: float = low
	var until: int = Time.get_ticks_msec() + int(transports._lifts[lift]["period"] * 1000.0) + 500
	while Time.get_ticks_msec() < until:
		await get_tree().physics_frame
		low = minf(low, node.global_position.y)
		high = maxf(high, node.global_position.y)
	print("lift travelled %.1f yards" % (high - low))
	_check(high - low > 5.0, "and the car rides up and down its shaft")

	var aboard: bool = false
	var was: Vector3 = Vector3.ZERO
	for attempt: int in BOARD_FRAMES:
		var deck: Vector3 = _deck_under(node)
		if deck != Vector3.INF:
			player.global_position = deck + Vector3(0.0, STAND, 0.0)
		await get_tree().physics_frame
		aboard = player.on_transport()
		if aboard:
			was = player.global_position
			break
		if not is_instance_valid(node):
			break
	_check(aboard, "standing on the car names it underfoot")
	if not aboard:
		var bodies: Array[Node] = node.find_children("*", "StaticBody3D", true, false)
		printerr("car at ", node.global_position, " bodies ", bodies.size())
		for body: Node in bodies:
			for shape: Node in body.find_children("*", "CollisionShape3D", true, false):
				var poly: ConcavePolygonShape3D = (shape as CollisionShape3D).shape
				printerr("  shape faces ", poly.get_faces().size() if poly else -1,
					" layer ", (body as StaticBody3D).collision_layer)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			node.global_position + Vector3(0.0, PROBE, 0.0),
			node.global_position - Vector3(0.0, PROBE, 0.0),
		)
		printerr("raw ray: ", node.get_world_3d().direct_space_state.intersect_ray(query))
		return
	await _frames(SAIL_FRAMES)
	print("the lift carried them %.1f yards" % was.distance_to(player.global_position))
	_check(was.distance_to(player.global_position) > 1.0, "and the car carries them with it")
	_check(player.transport_guid() == 0, "but claims no transport on the wire")
	_check(
		WowClient.session.get_state() == WowSession.STATE_IN_WORLD,
		"and the server keeps taking the movement",
	)


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
		if aboard or not is_instance_valid(node):
			break
	_check(aboard, "standing on the deck names the transport")
	if not aboard:
		return
	# Measured from aboard, because a zeppelin watched from the shore sails out of view and despawns.
	var hull: Vector3 = node.global_position
	var seat: Vector3 = player.transport_offset()
	var was: Vector3 = player.global_position
	await _frames(SAIL_FRAMES)
	var sailed: float = hull.distance_to(node.global_position)
	var carried: float = was.distance_to(player.global_position)
	var drift: float = seat.distance_to(player.transport_offset())
	print("it sailed %.1f, carried %.1f yards, seat drifted %.2f" % [sailed, carried, drift])
	_check(sailed > 1.0, "and sails along the path")
	_check(carried > 1.0, "and the deck carries them along with it")
	_check(drift < 2.0, "while their place on it stays put")
	_check(
		WowClient.session.get_state() == WowSession.STATE_IN_WORLD,
		"and the server takes the movement it is told",
	)


# The first surface of the transport flat enough to stand on: a lift car has a slanted roof frame.
func _deck_under(node: Node3D) -> Vector3:
	if not is_instance_valid(node):
		return Vector3.INF
	var space: PhysicsDirectSpaceState3D = node.get_world_3d().direct_space_state
	var from: Vector3 = node.global_position + Vector3(0.0, PROBE, 0.0)
	var to: Vector3 = node.global_position - Vector3(0.0, PROBE, 0.0)
	for step: int in 8:
		var hit: Dictionary = space.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, to)
		)
		if hit.is_empty():
			return Vector3.INF
		if node.is_ancestor_of(hit["collider"]) and (hit["normal"] as Vector3).y > 0.7:
			return hit["position"]
		from = (hit["position"] as Vector3) - Vector3(0.0, 0.05, 0.0)
	return Vector3.INF


func _object_with_entry(entry: int) -> int:
	var session: WowSession = WowClient.session
	for guid: int in session.get_object_guids():
		if session.get_field(guid, "OBJECT_FIELD_ENTRY") == entry:
			return guid
	return 0


func _teleport(wow_position: Vector3, map_id: int) -> void:
	WowClient.session.send_chat(
		WowSession.CHAT_SAY,
		".go xyz %f %f %f %d" % [wow_position.x, wow_position.y, wow_position.z, map_id],
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
