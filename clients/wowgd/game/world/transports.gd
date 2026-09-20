class_name Transports
extends Node

# GameObject type 15: a boat or zeppelin that sails a taxi path of its own.
const TYPE_MO_TRANSPORT: int = 15
# Its type data: the taxi path it runs and how fast it goes along it.
enum Data { PATH, SPEED }

## The map the transports sail on; changing it drops the routes of the map just left.
var map_id: int = -1:
	set(value):
		map_id = value
		_routes.clear()
		_pending.clear()

var _entities: Entities
# Per transport guid: {"points": PackedVector3Array, "lengths": PackedFloat32Array,
# "period": float, "phase": float}
var _routes: Dictionary[int, Dictionary] = {}
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
		if node == null:
			continue
		var route: Dictionary = _routes[guid]
		route["phase"] = fmod(route["phase"] + delta, route["period"])
		_place(node, route)


# Where the transport stands now, and which way it is heading.
func _place(node: Node3D, route: Dictionary) -> void:
	var points: PackedVector3Array = route["points"]
	var lengths: PackedFloat32Array = route["lengths"]
	var left: float = route["phase"] * route["speed"]
	for i: int in lengths.size():
		if left > lengths[i]:
			left -= lengths[i]
			continue
		var from: Vector3 = points[i]
		var to: Vector3 = points[i + 1]
		var heading: Basis = Basis(Vector3.UP, atan2(-(to.x - from.x), -(to.z - from.z)))
		node.global_transform = Transform3D(
			heading.scaled(node.scale), from.lerp(to, left / maxf(lengths[i], 0.001))
		)
		return


# The server places a transport once and never again, so the only sync point is that first position.
func _travelled(points: PackedVector3Array, lengths: PackedFloat32Array, at: Vector3) -> float:
	var best: float = INF
	var found: float = 0.0
	var walked: float = 0.0
	for i: int in lengths.size():
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
		_pending.erase(guid)


# A route is the path's points on this map, with the length of each leg so the phase can walk it.
func _register(guid: int, info: Dictionary) -> void:
	if info.get("type", 0) != TYPE_MO_TRANSPORT:
		return
	var fields: PackedInt32Array = info.get("data", PackedInt32Array())
	if fields.size() <= Data.SPEED:
		return
	var points: PackedVector3Array = TaxiNodes.path_points(fields[Data.PATH], map_id)
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
	_routes[guid] = {
		"points": points, "lengths": lengths, "speed": speed, "period": total / speed,
		"phase": _travelled(points, lengths, here) / speed,
	}
	var node: Node3D = _entities.unit_node(guid)
	if node:
		node.set_meta(Player.TRANSPORT_META, guid)
