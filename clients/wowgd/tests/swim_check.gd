class_name SwimCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const LOAD_MSEC: int = 60000
const STEP_MSEC: int = 8000
# The lake in Loch Modan, deep enough to swim in, and Coldridge Valley to come home to.
const LAKE: Vector3 = Vector3(-5289.82, -3482.56, 297.605)
const HOME: Vector3 = Vector3(-6248.77, 317.339, 382.778)
const DROP_HEIGHT: float = 3.0
const SEARCH_STEP: float = 20.0
const SEARCH_RINGS: int = 10
const DEEP_ENOUGH: float = 4.0
const BOTTOM_REACH: float = 60.0
const SWIM_FRAMES: int = 90
const DIVE_PITCH: float = -1.2
const RISE_PITCH: float = 0.5

var _failures: PackedStringArray = []
var _main: Main
var _sent: PackedStringArray = []


# Falls into a lake, swims down and back to the surface, then leaves the water.
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
	var player: Player = _main.world.player()
	player.movement_changed.connect(_on_movement_changed)
	await _teleport(LAKE)
	var surface: Vector3 = _water_near(player.global_position)
	if is_nan(surface.y):
		return _finish("no water near the lake teleport")
	print("water at ", surface, " depth ", _depth(surface))
	var wow_surface: Vector3 = WowCoords.from_godot(surface)
	await _teleport(Vector3(wow_surface.x, wow_surface.y, wow_surface.z + DROP_HEIGHT))
	var swimming_by: int = Time.get_ticks_msec() + STEP_MSEC
	while not "MSG_MOVE_START_SWIM" in _sent and Time.get_ticks_msec() < swimming_by:
		await get_tree().process_frame
	_check("MSG_MOVE_START_SWIM" in _sent, "falling into the lake starts a swim")
	var floating: float = player.global_position.y
	_check(absf(floating - surface.y) < 2.0, "the player floats at the surface")

	_pitch(DIVE_PITCH)
	Input.action_press("move_forward")
	await _frames(SWIM_FRAMES)
	var deep: float = player.global_position.y
	_check(deep < floating - 2.0, "swimming forward while looking down dives")
	_pitch(RISE_PITCH)
	await _frames(SWIM_FRAMES)
	Input.action_release("move_forward")
	var risen: float = player.global_position.y
	_check(risen > deep + 1.0, "swimming forward while looking up rises")
	_check(risen <= surface.y + 0.1, "the player cannot swim out of the water")
	print("surface ", surface.y, " dived to ", deep, " rose to ", risen)

	_sent.clear()
	await _teleport(HOME)
	var stopped_by: int = Time.get_ticks_msec() + STEP_MSEC
	while not "MSG_MOVE_STOP_SWIM" in _sent and Time.get_ticks_msec() < stopped_by:
		await get_tree().process_frame
	_check("MSG_MOVE_STOP_SWIM" in _sent, "leaving the water stops the swim")
	_check(session.get_state() == WowSession.STATE_IN_WORLD, "the server kept the session")
	_finish("")


# The nearest liquid surface with DEEP_ENOUGH water under it.
func _water_near(godot_position: Vector3) -> Vector3:
	var map: WowMap = _main.world.get_node("WowMap")
	for ring: int in SEARCH_RINGS + 1:
		for x: int in range(-ring, ring + 1):
			for z: int in range(-ring, ring + 1):
				if ring > 0 and absi(x) != ring and absi(z) != ring:
					continue
				var at: Vector3 = godot_position + Vector3(x, 0.0, z) * SEARCH_STEP
				var height: float = map.liquid_height_at(at)
				if is_nan(height):
					continue
				var surface: Vector3 = Vector3(at.x, height, at.z)
				if _depth(surface) >= DEEP_ENOUGH:
					return surface
	return Vector3(godot_position.x, NAN, godot_position.z)


func _depth(surface: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = _main.world.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		surface + Vector3.UP, surface + Vector3.DOWN * BOTTOM_REACH
	)
	var hit: Dictionary = space.intersect_ray(query)
	return surface.y - hit["position"].y if hit.has("position") else 0.0


func _teleport(wow_position: Vector3) -> void:
	WowClient.session.send_chat(
		WowSession.CHAT_SAY, ".go xyz %f %f %f" % [wow_position.x, wow_position.y, wow_position.z]
	)
	var loaded_by: int = Time.get_ticks_msec() + LOAD_MSEC
	await _frames(30)
	while not _main.world.player().active and Time.get_ticks_msec() < loaded_by:
		await get_tree().process_frame
	await _frames(60)


func _pitch(radians: float) -> void:
	var pivot: Node3D = _main.world.player().get_node("CameraPivot")
	pivot.rotation.x = radians


func _on_movement_changed(
	opcode: String, _position: Vector3, _orientation: float, _flags: int,
	_fall_time_msec: int, _jump_velocity: Vector3, _ack_counter: int, _ack_tail: PackedByteArray,
) -> void:
	_sent.append(opcode)


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
	print("swim_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
