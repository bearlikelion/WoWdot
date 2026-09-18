class_name Entities
extends Node3D

enum ObjectType { UNIT = 3, PLAYER = 4, GAMEOBJECT = 5 }

const NAMEPLATE: PackedScene = preload("res://game/world/nameplate.tscn")
# Server paths faster than this (yards per second) play the run animation.
const RUN_SPEED_THRESHOLD: float = 4.0
const FORWARD_FLAG: int = 0x1
const NAMEPLATE_GAP: float = 0.3

var _nodes: Dictionary[int, Node3D] = {}
# Model-space bounds of units and players, used for picking.
var _bounds: Dictionary[int, AABB] = {}
var _nameplates: Dictionary[int, Label3D] = {}
var _paths: Dictionary[int, Path] = {}
var _game_object_displays: WowDBC


func _ready() -> void:
	_game_object_displays = WowDBC.open(WowAssets.archive, "GameObjectDisplayInfo")
	var session: WowSession = WowClient.session
	session.object_created.connect(_on_object_created)
	session.object_moved.connect(_on_object_moved)
	session.objects_destroyed.connect(_on_objects_destroyed)
	session.name_received.connect(_on_name_received)
	# Objects that arrived before the world scene existed.
	for guid: int in session.get_object_guids():
		_on_object_created(guid, session.get_object_type(guid))


func _process(delta: float) -> void:
	for guid: int in _paths.keys():
		var path: Path = _paths[guid]
		var node: Node3D = _nodes.get(guid)
		if node == null:
			_paths.erase(guid)
			continue
		path.elapsed += delta
		var weight: float = clampf(path.elapsed / path.duration, 0.0, 1.0)
		node.global_position = path.from.lerp(path.to, weight)
		if weight >= 1.0:
			_paths.erase(guid)
			_play(node, "Stand")


func _on_object_created(guid: int, type_id: int) -> void:
	var session: WowSession = WowClient.session
	if guid == session.get_player_guid() or _nodes.has(guid):
		return
	var node: Node3D = null
	var display: int = session.get_field(guid, "UNIT_FIELD_DISPLAYID")
	match type_id:
		ObjectType.UNIT:
			node = WowAssets.creatures.instantiate(display)
		ObjectType.PLAYER:
			node = WowAssets.creatures.instantiate(display, CharacterModels.player_look(session, guid))
		ObjectType.GAMEOBJECT:
			node = _game_object(guid)
	if node == null:
		return
	add_child(node)
	node.global_position = WowCoords.to_godot(session.get_object_position(guid))
	_nodes[guid] = node
	if type_id != ObjectType.GAMEOBJECT:
		node.rotation.y = session.get_object_orientation(guid)
		_add_nameplate(guid, node)


func _on_object_moved(guid: int, movement: Dictionary) -> void:
	var node: Node3D = _nodes.get(guid)
	if node == null:
		return
	if movement.has("destination"):
		var to: Vector3 = WowCoords.to_godot(movement["destination"])
		var duration: float = maxf(int(movement["duration_msec"]) / 1000.0, 0.001)
		var distance: float = node.global_position.distance_to(to)
		if distance < 0.01:
			return
		var path: Path = Path.new()
		path.from = node.global_position
		path.to = to
		path.duration = duration
		_paths[guid] = path
		var heading: Vector3 = WowCoords.from_godot(to) - WowCoords.from_godot(path.from)
		node.rotation.y = atan2(heading.y, heading.x)
		_play(node, "Run" if distance / duration > RUN_SPEED_THRESHOLD else "Walk")
		return
	_paths.erase(guid)
	node.global_position = WowCoords.to_godot(movement["position"])
	if movement.has("orientation"):
		node.rotation.y = movement["orientation"]
	_play(node, "Run" if int(movement.get("flags", 0)) & FORWARD_FLAG else "Stand")


# The nearest unit or player whose bounds the ray crosses, or 0.
func pick(from: Vector3, direction: Vector3) -> int:
	var picked: int = 0
	var nearest: float = INF
	for guid: int in _bounds:
		var box: AABB = _nodes[guid].global_transform * _bounds[guid]
		var hit: Variant = box.intersects_ray(from, direction)
		if hit != null and from.distance_to(hit) < nearest:
			nearest = from.distance_to(hit)
			picked = guid
	return picked


func _on_name_received(guid: int, unit_name: String) -> void:
	if _nameplates.has(guid):
		_nameplates[guid].text = unit_name


func _on_objects_destroyed(guids: PackedInt64Array) -> void:
	for guid: int in guids:
		_paths.erase(guid)
		_bounds.erase(guid)
		_nameplates.erase(guid)
		if _nodes.has(guid):
			_nodes[guid].queue_free()
			_nodes.erase(guid)


func _add_nameplate(guid: int, node: Node3D) -> void:
	var to_local: Transform3D = node.global_transform.affine_inverse()
	var bounds: AABB = AABB()
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = to_local * mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(box) if bounds.has_volume() else box
	_bounds[guid] = bounds
	var plate: Label3D = NAMEPLATE.instantiate()
	plate.position.y = bounds.end.y + NAMEPLATE_GAP / node.scale.y
	plate.scale = Vector3.ONE / node.scale
	plate.text = WowClient.session.get_object_name(guid)
	node.add_child(plate)
	_nameplates[guid] = plate


func _game_object(guid: int) -> Node3D:
	var session: WowSession = WowClient.session
	var row: int = _game_object_displays.find(session.get_field(guid, "GAMEOBJECT_DISPLAYID"))
	if row < 0:
		return null
	var path: String = _game_object_displays.get_string(row, "ModelName")
	var node: Node3D = null
	if path.to_lower().ends_with(".wmo"):
		node = WowAssets.loader.load_wmo(path)
	elif not path.is_empty():
		node = WowAssets.loader.load_m2(path)
	if node == null:
		return null
	# GAMEOBJECT_ROTATION is a WoW-space quaternion; an empty one means only the facing is set.
	var base: int = session.field_index("GAMEOBJECT_ROTATION")
	var x: float = session.get_field_float(guid, base)
	var y: float = session.get_field_float(guid, base + 1)
	var z: float = session.get_field_float(guid, base + 2)
	var w: float = session.get_field_float(guid, base + 3)
	if Vector4(x, y, z, w).length_squared() > 0.5:
		node.quaternion = Quaternion(-y, z, -x, w).normalized()
	else:
		node.rotation.y = session.get_field_float(guid, "GAMEOBJECT_FACING")
	return node


func _play(node: Node3D, animation: String) -> void:
	var player: AnimationPlayer = node.get_node_or_null("AnimationPlayer")
	if player and player.current_animation != animation and player.has_animation(animation):
		player.play(animation, 0.2)


class Path:
	var from: Vector3
	var to: Vector3
	var duration: float
	var elapsed: float = 0.0
