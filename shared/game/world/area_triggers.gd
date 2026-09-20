class_name AreaTriggers
extends Node

signal entered(trigger_id: int)

# The server allows five yards of slack, so there is no need to test every frame.
const CHECK_SECONDS: float = 0.2

## The map whose triggers are watched; changing it reloads them and adopts whatever is underfoot.
var map_id: int = -1:
	set(value):
		if map_id == value:
			return
		map_id = value
		_adopt = true
		_load()

var _player: Player
# Per trigger on this map: "id", "at", "radius", "box", "yaw", all in WoW coordinates.
var _triggers: Array[Dictionary] = []
var _inside: int = 0
var _adopt: bool = false
var _elapsed: float = 0.0


# Instance portals and trigger-based quest objectives only fire once the client reports the entry.
func watch(player: Player) -> void:
	_player = player


## Landing inside a trigger is not walking into one: a portal would bounce the player straight back.
func settle() -> void:
	_adopt = true


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < CHECK_SECONDS:
		return
	_elapsed = 0.0
	if _player == null or not _player.active or _triggers.is_empty():
		return
	var found: int = _trigger_at(WowCoords.from_godot(_player.global_position))
	if _adopt:
		_adopt = false
		_inside = found
		return
	if found == _inside:
		return
	_inside = found
	if found == 0:
		return
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_u32(0, found)
	WowClient.session.send_packet("CMSG_AREATRIGGER", payload)
	entered.emit(found)


# A trigger is either a sphere or, when it has no radius, a box turned about the vertical axis.
func _trigger_at(at: Vector3) -> int:
	for trigger: Dictionary in _triggers:
		var away: Vector3 = at - (trigger["at"] as Vector3)
		var radius: float = trigger["radius"]
		if radius > 0.0:
			if away.length_squared() <= radius * radius:
				return trigger["id"]
			continue
		var turn: float = TAU - (trigger["yaw"] as float)
		var box: Vector3 = trigger["box"]
		var along: float = away.x * cos(turn) - away.y * sin(turn)
		var across: float = away.y * cos(turn) + away.x * sin(turn)
		if absf(along) <= box.x * 0.5 and absf(across) <= box.y * 0.5 \
		and absf(away.z) <= box.z * 0.5:
			return trigger["id"]
	return 0


func _load() -> void:
	_triggers.clear()
	if map_id < 0:
		return
	var dbc: WowDBC = WowDBC.open(WowAssets.archive, "AreaTrigger")
	if dbc == null:
		return
	for row: int in dbc.row_count():
		if dbc.get_uint(row, "MapID") != map_id:
			continue
		_triggers.append({
			"id": dbc.get_uint(row, "ID"),
			"at": Vector3(
				dbc.get_float(row, "X"), dbc.get_float(row, "Y"), dbc.get_float(row, "Z")
			),
			"radius": dbc.get_float(row, "Radius"),
			"box": Vector3(
				dbc.get_float(row, "BoxLength"),
				dbc.get_float(row, "BoxWidth"),
				dbc.get_float(row, "BoxHeight"),
			),
			"yaw": dbc.get_float(row, "BoxYaw"),
		})
