class_name Entities
extends Node3D

enum ObjectType { UNIT = 3, PLAYER = 4, GAMEOBJECT = 5 }

const NAMEPLATE: PackedScene = preload("res://game/world/nameplate.tscn")
# Server paths faster than this (yards per second) play the run animation.
const RUN_SPEED_THRESHOLD: float = 4.0
const NAMEPLATE_GAP: float = 0.3
# The gold the stock client draws your own name in.
const OWN_NAME_COLOR: Color = Color(1.0, 0.9, 0.55)
# The quest marker floats this far over the top line of the nameplate.
const MARKER_GAP: float = 0.3
const NAMEPLATE_LINE_HEIGHT: float = 0.3
# SMSG_ATTACKERSTATEUPDATE victim state for a blow that landed.
const VICTIM_STATE_HIT: int = 1

var _nodes: Dictionary[int, Node3D] = {}
# Model-space bounds of units and players, used for picking.
var _bounds: Dictionary[int, AABB] = {}
var _nameplates: Dictionary[int, Label3D] = {}
# Units auto-attacking, by the guid they attack; like the stock client they turn to face it.
var _victims: Dictionary[int, int] = {}
# Players' visible item entries, and those whose gear still waits on item queries.
var _worn: Dictionary[int, PackedInt32Array] = {}
var _dressing: Dictionary[int, bool] = {}
# Weapons each unit carries and the sheath state they were last hung for.
var _weapons: Dictionary[int, Array] = {}
var _sheath_states: Dictionary[int, ItemModels.SheathState] = {}
var _paths: Dictionary[int, Path] = {}
# Other players, carried forward between their relayed movement packets.
var _motions: Dictionary[int, RemoteMotion] = {}
var _game_object_displays: WowDBC
var _quest_givers: Dictionary[int, bool] = {}
var _markers: Dictionary[int, Node3D] = {}
# What quest givers offer depends on the quest log and level, so either changing asks again.
var _quest_state: Array = []


func _ready() -> void:
	WowAssets.interface.changed.connect(func() -> void:
		for guid: int in _nameplates:
			_show_name(guid)
	)
	_game_object_displays = WowDBC.open(WowAssets.archive, "GameObjectDisplayInfo")
	var session: WowSession = WowClient.session
	session.object_created.connect(_on_object_created)
	session.object_moved.connect(_on_object_moved)
	session.objects_destroyed.connect(_on_objects_destroyed)
	session.name_received.connect(_on_name_received)
	session.object_updated.connect(_on_object_updated)
	session.melee_swing.connect(_on_melee_swing)
	session.item_info_received.connect(_on_item_info_received)
	session.attack_started.connect(_on_attack_changed.bind(true))
	session.attack_stopped.connect(_on_attack_changed.bind(false))
	session.quest_giver_status_received.connect(_on_quest_giver_status)
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
			if not is_nan(path.facing):
				node.rotation.y = path.facing
			_play_idle(guid, node)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for guid: int in _motions:
		var node: Node3D = _nodes.get(guid)
		if node:
			node.global_position = _motions[guid].advance(delta, space)
			node.rotation.y = _motions[guid].orientation
	for guid: int in _victims:
		if not _paths.has(guid) and not _motions.has(guid) and _nodes.has(guid):
			_face(_nodes[guid], _victims[guid])


func _on_object_created(guid: int, type_id: int) -> void:
	var session: WowSession = WowClient.session
	if guid == session.get_player_guid() or _nodes.has(guid):
		return
	var node: Node3D = null
	var display: int = session.get_field(guid, "UNIT_FIELD_DISPLAYID")
	match type_id:
		ObjectType.UNIT:
			node = WowAssets.creatures.instantiate(display)
			_weapons[guid] = ItemModels.unit_weapons(session, guid)
		ObjectType.PLAYER:
			var look: Dictionary = CharacterModels.player_look(session, guid)
			_worn[guid] = CharacterModels.visible_items(session, guid)
			_weapons[guid] = look["weapons"]
			_sheath_states[guid] = look["sheath_state"]
			if look["pending"]:
				_dressing[guid] = true
			node = WowAssets.creatures.instantiate(display, look)
		ObjectType.GAMEOBJECT:
			node = _game_object(guid)
	if node == null:
		return
	add_child(node)
	node.global_position = WowCoords.to_godot(session.get_object_position(guid))
	_nodes[guid] = node
	if type_id == ObjectType.UNIT:
		_arm(guid)
	if type_id != ObjectType.GAMEOBJECT:
		node.rotation.y = session.get_object_orientation(guid)
		add_nameplate(guid, node)
		UnitVoice.attach(node, guid, display)
		_on_object_updated(guid)
		if type_id == ObjectType.UNIT and NpcDialog.is_quest_giver(guid):
			_quest_givers[guid] = true
			NpcDialog.send("CMSG_QUESTGIVER_STATUS_QUERY", guid)


func _on_object_moved(guid: int, movement: Dictionary) -> void:
	var node: Node3D = _nodes.get(guid)
	if node == null:
		return
	if movement.has("destination"):
		var to: Vector3 = WowCoords.to_godot(movement["destination"])
		var duration: float = maxf(int(movement["duration_msec"]) / 1000.0, 0.001)
		var distance: float = node.global_position.distance_to(to)
		if distance < 0.01:
			if movement.has("orientation"):
				node.rotation.y = movement["orientation"]
			return
		var path: Path = Path.new()
		path.from = node.global_position
		path.to = to
		path.duration = duration
		path.facing = movement.get("orientation", NAN)
		_paths[guid] = path
		node.rotation.y = _heading(path.from, to)
		UnitAnimations.set_base(node, ["Run" if distance / duration > RUN_SPEED_THRESHOLD else "Walk"])
		return
	_paths.erase(guid)
	if movement.has("flags"):
		var motion: RemoteMotion = _motions.get(guid)
		if motion == null:
			motion = RemoteMotion.new()
			_motions[guid] = motion
		motion.update(movement, node.global_position)
		var clips: PackedStringArray = UnitAnimations.movement_clips(motion.flags)
		if clips.is_empty():
			_play_idle(guid, node)
		else:
			UnitAnimations.set_base(node, clips)
		return
	node.global_position = WowCoords.to_godot(movement["position"])
	if movement.has("orientation"):
		node.rotation.y = movement["orientation"]
	_play_idle(guid, node)


# Every object that currently has a node.
func shown_guids() -> PackedInt64Array:
	return PackedInt64Array(_nodes.keys())


func nameplate(guid: int) -> Label3D:
	return _nameplates.get(guid)


func unit_node(guid: int) -> Node3D:
	return _nodes.get(guid)


# The top of the unit's model in world space, or ZERO for a unit that is not shown.
func head_position(guid: int) -> Vector3:
	if not _nodes.has(guid) or not _bounds.has(guid):
		return Vector3.ZERO
	return _nodes[guid].global_transform * Vector3(0.0, _bounds[guid].end.y, 0.0)


# Half the unit's footprint across, scaled as drawn, or 0 for a unit that is not shown.
func unit_radius(guid: int) -> float:
	if not _nodes.has(guid) or not _bounds.has(guid):
		return 0.0
	var box: AABB = _bounds[guid]
	return maxf(box.size.x, box.size.z) * 0.5 * _nodes[guid].scale.x


# Units and players within range of the point that the camera can see, nearest first.
func visible_units(from: Vector3, max_distance: float, camera: Camera3D) -> Array[int]:
	var found: Array[int] = []
	var distances: Dictionary[int, float] = {}
	for guid: int in _bounds:
		var node: Node3D = _nodes[guid]
		var distance: float = from.distance_to(node.global_position)
		if distance <= max_distance \
		and camera.is_position_in_frustum(node.global_transform * _bounds[guid].get_center()):
			found.append(guid)
			distances[guid] = distance
	found.sort_custom(func(a: int, b: int) -> bool: return distances[a] < distances[b])
	return found


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


func _arm(guid: int) -> void:
	var session: WowSession = WowClient.session
	var state: ItemModels.SheathState = ItemModels.sheath_state(session, guid)
	_sheath_states[guid] = state
	var model_path: String = WowAssets.creatures.model_path(
		session.get_field(guid, "UNIT_FIELD_DISPLAYID")
	)
	WowAssets.characters.item_models.arm(_nodes[guid], model_path, _weapons[guid], state)


func _on_name_received(guid: int, _unit_name: String) -> void:
	if _nameplates.has(guid):
		_nameplates[guid].text = _plate_text(guid)
		_color_name(guid)
		_place_marker(guid)


# FACTION_BAR_COLORS: a unit's name reads red, yellow or green by how it feels about the player.
func _color_name(guid: int) -> void:
	if not _nameplates.has(guid):
		return
	var session: WowSession = WowClient.session
	if guid == session.get_player_guid():
		return
	var reaction: UnitReaction.Reaction = UnitReaction.between(
		session, session.get_player_guid(), guid
	)
	_nameplates[guid].modulate = UnitReaction.COLORS.get(reaction, OWN_NAME_COLOR)


# The stock options hide your own name, other players' and creatures' separately.
func _show_name(guid: int) -> void:
	if not _nameplates.has(guid):
		return
	var session: WowSession = WowClient.session
	var option: StringName = &"show_own_name"
	if guid != session.get_player_guid():
		option = &"show_player_names" if session.get_object_type(guid) == ObjectType.PLAYER \
		else &"show_npc_names"
	_nameplates[guid].visible = WowAssets.interface.is_on(option)


# The name, and under it the creature's title such as <Paladin Trainer>.
func _plate_text(guid: int) -> String:
	var session: WowSession = WowClient.session
	var title: String = session.get_creature_info(guid).get("subname", "")
	var unit_name: String = session.get_object_name(guid)
	return unit_name + ("\n<%s>" % title if not title.is_empty() else "")


func _on_objects_destroyed(guids: PackedInt64Array) -> void:
	for guid: int in guids:
		_paths.erase(guid)
		_motions.erase(guid)
		_bounds.erase(guid)
		_nameplates.erase(guid)
		_victims.erase(guid)
		_worn.erase(guid)
		_dressing.erase(guid)
		_weapons.erase(guid)
		_sheath_states.erase(guid)
		_quest_givers.erase(guid)
		_markers.erase(guid)
		NpcDialog.statuses.erase(guid)
		if _nodes.has(guid):
			_nodes[guid].queue_free()
			_nodes.erase(guid)


# The player's own model is not one of these entities, so world.gd asks for its plate itself.
func add_nameplate(guid: int, node: Node3D) -> void:
	var node_space: Transform3D = node.global_transform.affine_inverse()
	var bounds: AABB = AABB()
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = node_space * mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(box) if bounds.has_volume() else box
	# Only tracked entities go in _bounds; the player's own model is not one, and picking walks it.
	if _nodes.has(guid):
		_bounds[guid] = bounds
	var plate: Label3D = NAMEPLATE.instantiate()
	plate.position.y = bounds.end.y + NAMEPLATE_GAP / node.scale.y
	plate.scale = Vector3.ONE / node.scale
	plate.text = _plate_text(guid)
	node.add_child(plate)
	_nameplates[guid] = plate
	_color_name(guid)
	_show_name(guid)


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid():
		_refresh_quest_givers()
	var node: Node3D = _nodes.get(guid)
	if node == null or not _bounds.has(guid):
		return
	if _worn.has(guid) and _worn[guid] != CharacterModels.visible_items(WowClient.session, guid):
		_respawn(guid)
		return
	if _sheath_states.has(guid) \
	and _sheath_states[guid] != ItemModels.sheath_state(WowClient.session, guid):
		_arm(guid)
	var alive: bool = WowClient.session.get_field(guid, "UNIT_FIELD_HEALTH") > 0
	if not alive:
		UnitAnimations.die(node)
	elif UnitAnimations.is_dead(node):
		UnitAnimations.revive(node)


func _refresh_quest_givers() -> void:
	var session: WowSession = WowClient.session
	var state: Array = [session.get_field(session.get_player_guid(), "UNIT_FIELD_LEVEL")]
	for slot: int in QuestLog.slots():
		state.append(QuestLog.quest_id(slot))
		state.append(QuestLog.state(slot))
	if state == _quest_state:
		return
	_quest_state = state
	for guid: int in _quest_givers:
		NpcDialog.send("CMSG_QUESTGIVER_STATUS_QUERY", guid)


func _on_quest_giver_status(guid: int, status: int) -> void:
	NpcDialog.statuses[guid] = status as NpcDialog.Status
	var node: Node3D = _nodes.get(guid)
	if node == null or not _bounds.has(guid):
		return
	if _markers.has(guid):
		_markers[guid].queue_free()
		_markers.erase(guid)
	var path: String = NpcDialog.MARKERS.get(status, "")
	if path.is_empty():
		return
	var marker: Node3D = WowAssets.loader.load_m2(path)
	if marker == null:
		return
	node.add_child(marker)
	marker.scale = Vector3.ONE / node.scale
	UnitAnimations.set_base(marker, ["Stand"])
	_markers[guid] = marker
	_place_marker(guid)


# Above the nameplate's top line, however many lines it has.
func _place_marker(guid: int) -> void:
	if not _markers.has(guid) or not _nodes.has(guid):
		return
	var lines: int = _nameplates[guid].text.count("\n") + 1 if _nameplates.has(guid) else 0
	var above: float = NAMEPLATE_GAP + lines * NAMEPLATE_LINE_HEIGHT + MARKER_GAP
	_markers[guid].position.y = _bounds[guid].end.y + above / _nodes[guid].scale.y


func _on_melee_swing(
	attacker: int, victim: int, damage: int, _hit_info: int, victim_state: int,
) -> void:
	if _nodes.has(attacker):
		UnitAnimations.play_once(_nodes[attacker], UnitAnimations.ATTACK)
	if _nodes.has(victim) and damage > 0 and victim_state == VICTIM_STATE_HIT:
		UnitAnimations.play_once(_nodes[victim], UnitAnimations.WOUND)


func _on_attack_changed(attacker: int, victim: int, attacking: bool) -> void:
	if not _nodes.has(attacker):
		return
	if attacking:
		_victims[attacker] = victim
	else:
		_victims.erase(attacker)
	if not _paths.has(attacker):
		_play_idle(attacker, _nodes[attacker])
		if attacking:
			_face(_nodes[attacker], victim)


func _on_item_info_received(_entry: int) -> void:
	for guid: int in _dressing.keys():
		if not CharacterModels.player_look(WowClient.session, guid)["pending"]:
			_dressing.erase(guid)
			_respawn(guid)


# Re-dressing keeps a running player's motion, so the new model keeps moving.
func _respawn(guid: int) -> void:
	var session: WowSession = WowClient.session
	var motion: RemoteMotion = _motions.get(guid)
	_on_objects_destroyed(PackedInt64Array([guid]))
	_on_object_created(guid, session.get_object_type(guid))
	if motion and _nodes.has(guid):
		_motions[guid] = motion


func _play_idle(guid: int, node: Node3D) -> void:
	var idle: PackedStringArray = UnitAnimations.READY if _victims.has(guid) \
	else PackedStringArray(["Stand"])
	UnitAnimations.set_base(node, idle)


func _face(node: Node3D, target: int) -> void:
	var at: Vector3 = WowCoords.to_godot(WowClient.session.get_object_position(target))
	if _nodes.has(target):
		at = _nodes[target].global_position
	if Vector2(at.x - node.global_position.x, at.z - node.global_position.z).length() > 0.01:
		node.rotation.y = _heading(node.global_position, at)


# The WoW orientation, which is also rotation.y, of the ground direction between two points.
func _heading(from: Vector3, to: Vector3) -> float:
	var heading: Vector3 = WowCoords.from_godot(to) - WowCoords.from_godot(from)
	return atan2(heading.y, heading.x)


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
	var turn: Vector4 = Vector4.ZERO
	if base >= 0:
		turn = Vector4(
			session.get_field_float(guid, base), session.get_field_float(guid, base + 1),
			session.get_field_float(guid, base + 2), session.get_field_float(guid, base + 3),
		)
	if turn.length_squared() > 0.5:
		node.quaternion = Quaternion(-turn.y, turn.z, -turn.x, turn.w).normalized()
	else:
		# WotLK dropped the facing field, leaving only the orientation the object arrived with.
		var facing: int = session.field_index("GAMEOBJECT_FACING")
		node.rotation.y = session.get_field_float(guid, facing) if facing >= 0 \
				else session.get_object_orientation(guid)
	return node


class Path:
	var from: Vector3
	var to: Vector3
	var duration: float
	var elapsed: float = 0.0
	var facing: float = NAN
