class_name TargetOfTargetCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 15000
const PREY: String = "Wolf"
const MELEE_GAP: float = 1.5

var _failures: PackedStringArray = []
var _main: Main


# Attacking a creature makes it target the player, which the target of target frame shows.
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
	await _frames(60)
	var session: WowSession = WowClient.session
	var me: int = session.get_player_guid()
	var prey: int = _nearest(PREY)
	if prey == 0:
		return _finish("no %s nearby" % PREY)
	var player: Player = _main.world.player()
	var entities: Entities = _main.world.get_node("Entities")
	var prey_node: Node3D = entities.unit_node(prey)
	var to_prey: Vector3 = prey_node.global_position - player.global_position
	to_prey.y = 0.0
	player.global_position = prey_node.global_position - to_prey.normalized() * MELEE_GAP
	player.rotation.y = atan2(-to_prey.x, -to_prey.z)
	player.movement_changed.emit(
		"MSG_MOVE_HEARTBEAT", player.global_position, player.orientation(), 0, 0, Vector3.ZERO,
		-1, PackedByteArray(),
	)
	await _frames(30)
	_main.world.select(prey)
	session.attack(prey)
	var fighting: bool = await _until(
		func() -> bool: return session.get_field_guid(prey, "UNIT_FIELD_TARGET") == me
	)
	_check(fighting, "the creature fights back")
	var frame: TargetOfTargetFrame = _main.world.hud().find_child(
		"TargetofTargetFrame", true, false
	)
	_check(frame != null and frame.is_visible_in_tree(), "the target of target frame shows")
	if frame:
		_check(frame.guid == me, "the target of target is the player")
	session.stop_attack()
	session.send_chat(WowSession.CHAT_SAY, ".die")
	await _frames(30)
	_main.world.select(0)
	await _frames(10)
	_check(
		frame != null and not frame.is_visible_in_tree(), "clearing the target hides the frame"
	)
	_finish("")


func _nearest(part: String) -> int:
	var session: WowSession = WowClient.session
	var here: Vector3 = session.get_object_position(session.get_player_guid())
	var best: int = 0
	var best_range: float = INF
	for guid: int in session.get_object_guids():
		if session.get_object_type(guid) != Entities.ObjectType.UNIT \
		or not session.get_object_name(guid).contains(part) \
		or session.get_field(guid, "UNIT_FIELD_HEALTH") == 0:
			continue
		var away: float = session.get_object_position(guid).distance_to(here)
		if away < best_range:
			best_range = away
			best = guid
	return best


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
	var result: String = "OK" if _failures.is_empty() else "%d failed" % _failures.size()
	print("target_of_target_check: ", result)
	get_tree().quit(0 if _failures.is_empty() else 1)
