class_name Transports
extends Node

signal route_registered(guid: int, entry: int)

# GameObject type 15 sails a taxi path; type 11 is a lift running a TransportAnimation loop.
const TYPE_TRANSPORT: int = 11
const TYPE_MO_TRANSPORT: int = 15
# Type 15's type data: the taxi path it runs and how fast it goes along it.
enum Data { PATH, SPEED }

## The map the transports sail on; changing it drops the routes of the map just left.
var map_id: int = -1:
	set(value):
		map_id = value
		_routes.clear()
		_lifts.clear()
		_pending.clear()

var _entities: Entities
# Per transport guid: {"points", "maps", "lengths", "speed", "period", "phase"}
var _routes: Dictionary[int, Dictionary] = {}
# Per lift guid: {"times", "offsets", "period", "rest"}
var _lifts: Dictionary[int, Dictionary] = {}
var _pending: Dictionary[int, bool] = {}


# The server never sends a transport's position after the first one, so the client sails it itself.
func watch(entities: Entities) -> void:
	_entities = entities
	var session: WowSession = WowClient.session
	session.object_created.connect(_on_object_created)
	session.objects_destroyed.connect(_on_objects_destroyed)
	session.game_object_info_received.connect(_on_info_received)


# On the physics step, since what moves is a body the player stands on.
func _physics_process(delta: float) -> void:
	for guid: int in _routes:
		var node: Node3D = _entities.unit_node(guid)
		if node == null or not node.is_inside_tree():
			continue
		var route: Dictionary = _routes[guid]
		route["phase"] = fmod(route["phase"] + delta, route["period"])
		_sail(node, route)
	for guid: int in _lifts:
		var node: Node3D = _entities.unit_node(guid)
		if node and node.is_inside_tree():
			_raise(node, _lifts[guid])


# Where the transport stands now, and which way it is heading.
func _sail(node: Node3D, route: Dictionary) -> void:
	var points: PackedVector3Array = route["points"]
	var maps: PackedInt32Array = route["maps"]
	var lengths: PackedFloat32Array = route["lengths"]
	var left: float = route["phase"] * route["speed"]
	for i: int in lengths.size():
		if left > lengths[i]:
			left -= lengths[i]
			continue
		node.visible = maps[i] == map_id
		if not node.visible:
			return
		var from: Vector3 = points[i]
		var to: Vector3 = points[i + 1]
		var heading: Basis = Basis(Vector3.UP, atan2(-(to.x - from.x), -(to.z - from.z)))
		node.global_transform = Transform3D(
			heading.scaled(node.scale), from.lerp(to, left / maxf(lengths[i], 0.001))
		)
		return


# A lift has no server side at all: it loops on the client's own clock, as the stock client does.
func _raise(node: Node3D, lift: Dictionary) -> void:
	var times: PackedFloat32Array = lift["times"]
	var offsets: PackedVector3Array = lift["offsets"]
	var at: float = fmod(Time.get_ticks_msec() / 1000.0, lift["period"])
	for i: int in times.size() - 1:
		if at > times[i + 1]:
			continue
		var span: float = times[i + 1] - times[i]
		var offset: Vector3 = offsets[i].lerp(
			offsets[i + 1], (at - times[i]) / maxf(span, 0.001)
		)
		node.global_position = (lift["rest"] as Transform3D) * offset
		return


# The server places a transport once and never again, so the only sync point is that first position.
func _travelled(route: Dictionary, at: Vector3) -> float:
	var points: PackedVector3Array = route["points"]
	var lengths: PackedFloat32Array = route["lengths"]
	var maps: PackedInt32Array = route["maps"]
	var best: float = INF
	var found: float = 0.0
	var walked: float = 0.0
	for i: int in lengths.size():
		# Two continents share a coordinate range, so only this map's legs can be the one it is on.
		if maps[i] != map_id:
			walked += lengths[i]
			continue
		var leg: Vector3 = points[i + 1] - points[i]
		var along: float = clampf(
			(at - points[i]).dot(leg) / maxf(leg.length_squared(), 0.001), 0.0, 1.0
		)
		var away: float = at.distance_to(points[i] + leg * along)
		if away < best:
			best = away
			found = walked + lengths[i] * along
		walked += lengths[i]
	return found


func _on_object_created(guid: int, type_id: int) -> void:
	if type_id != Entities.ObjectType.GAMEOBJECT:
		return
	var session: WowSession = WowClient.session
	var info: Dictionary = session.get_game_object_info(
		session.get_field(guid, "OBJECT_FIELD_ENTRY")
	)
	if info.is_empty():
		_pending[guid] = true
		return
	_register(guid, info)


func _on_info_received(entry: int) -> void:
	var session: WowSession = WowClient.session
	for guid: int in _pending.keys():
		if session.get_field(guid, "OBJECT_FIELD_ENTRY") != entry:
			continue
		_pending.erase(guid)
		_register(guid, session.get_game_object_info(entry))


func _on_objects_destroyed(guids: PackedInt64Array) -> void:
	for guid: int in guids:
		_routes.erase(guid)
		_lifts.erase(guid)
		_pending.erase(guid)


func _register(guid: int, info: Dictionary) -> void:
	match int(info.get("type", 0)):
		TYPE_MO_TRANSPORT:
			_register_route(guid, info)
		TYPE_TRANSPORT:
			_register_lift(guid, info)


# A route is the path's whole polyline, since a leg on another map still costs the phase its time.
func _register_route(guid: int, info: Dictionary) -> void:
	var fields: PackedInt32Array = info.get("data", PackedInt32Array())
	if fields.size() <= Data.SPEED:
		return
	var path: Dictionary = TaxiNodes.path_route(fields[Data.PATH])
	var points: PackedVector3Array = path["points"]
	if points.size() < 2:
		return
	var lengths: PackedFloat32Array = []
	var total: float = 0.0
	for i: int in points.size() - 1:
		lengths.append(points[i].distance_to(points[i + 1]))
		total += lengths[i]
	var speed: float = maxf(fields[Data.SPEED], 1.0)
	var here: Vector3 = WowCoords.to_godot(WowClient.session.get_object_position(guid))
	# ponytail: constant speed with no acceleration ramp, so the phase drifts against the server's.
	var route: Dictionary = {
		"points": points, "maps": path["maps"], "lengths": lengths, "speed": speed,
		"period": total / speed, "phase": 0.0,
	}
	route["phase"] = _travelled(route, here) / speed
	_routes[guid] = route
	_tag(guid, guid)
	route_registered.emit(guid, int(info.get("entry", 0)))


# A lift loops offsets from where it was spawned, so that placement is the frame they sit in.
func _register_lift(guid: int, info: Dictionary) -> void:
	var node: Node3D = _entities.unit_node(guid)
	if node == null:
		return
	# A lift is an M2, which carries no collision until something has to stand on it.
	WowAssets.loader.add_collision(node)
	var frames: Dictionary = TaxiNodes.lift_frames(info.get("entry", 0))
	var times: PackedFloat32Array = frames["times"]
	if times.size() < 2:
		return
	_lifts[guid] = {
		"times": times, "offsets": frames["offsets"], "period": times[times.size() - 1],
		"rest": node.global_transform,
	}
	# A lift is not a transport on the wire, so it carries the player without the movement flag.
	_tag(guid, 0)


func _tag(guid: int, wire_guid: int) -> void:
	var node: Node3D = _entities.unit_node(guid)
	if node:
		node.set_meta(Player.TRANSPORT_META, wire_guid)
