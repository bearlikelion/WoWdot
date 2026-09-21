class_name MovementCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const ACK_WAIT_MSEC: int = 5000
# vMaNGOS re-sends a change it saw no valid ack for after Movement.PendingAckResponseTime.
const SERVER_RESOLVE_MSEC: int = 5500
const SPELL_ENTANGLING_ROOTS: int = 339
const SPELL_SLOW_FALL: int = 130
const ROOTED_FRAMES: int = 30

var _failures: PackedStringArray = []
var _main: Main
var _me: int = 0
# Ack opcode to the flags and tail of its latest send.
var _acks: Dictionary[String, Array] = {}
var _sent: PackedStringArray = []
var _resolved: PackedStringArray = []


# GM speed, root, water walk, feather fall and knockback changes are applied and acked.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = "127.0.0.1"
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
	var player: Player = _main.world.player()
	_me = session.get_player_guid()
	_main.world.select(_me)
	player.movement_changed.connect(_on_movement_changed)
	session.object_moved.connect(_on_object_moved)
	session.packet_received.connect(_on_packet_received)

	var fast: Array = await _command(".modify speed 2", "CMSG_FORCE_RUN_SPEED_CHANGE_ACK")
	_check(not fast.is_empty() and is_equal_approx(_tail_float(fast), 14.0), "run speed doubles")
	var normal: Array = await _command(".modify speed 1", "CMSG_FORCE_RUN_SPEED_CHANGE_ACK")
	_check(not normal.is_empty() and is_equal_approx(_tail_float(normal), 7.0), "run speed resets")

	var rooted: Array = await _command(
		".aura %d" % SPELL_ENTANGLING_ROOTS, "CMSG_FORCE_MOVE_ROOT_ACK"
	)
	_check(not rooted.is_empty() and rooted[0] & Player.MoveFlag.ROOT, "the root ack is rooted")
	var start: Vector3 = player.global_position
	Input.action_press("move_forward")
	await _frames(ROOTED_FRAMES)
	Input.action_release("move_forward")
	_check(player.global_position.distance_to(start) < 0.05, "a rooted player cannot walk")
	var freed: Array = await _command(
		".unaura %d" % SPELL_ENTANGLING_ROOTS, "CMSG_FORCE_MOVE_UNROOT_ACK"
	)
	_check(not freed.is_empty() and not freed[0] & Player.MoveFlag.ROOT, "the unroot ack is free")

	var walking: Array = await _command(".cheat waterwalk on", "CMSG_MOVE_WATER_WALK_ACK")
	_check(not walking.is_empty() and _tail_u32(walking) == 1, "water walk turns on")
	var sinking: Array = await _command(".cheat waterwalk off", "CMSG_MOVE_WATER_WALK_ACK")
	_check(not sinking.is_empty() and _tail_u32(sinking) == 0, "water walk turns off")
	var slow: Array = await _command(".aura %d" % SPELL_SLOW_FALL, "CMSG_MOVE_FEATHER_FALL_ACK")
	_check(not slow.is_empty() and _tail_u32(slow) == 1, "feather fall turns on")
	var normal_fall: Array = await _command(
		".unaura %d" % SPELL_SLOW_FALL, "CMSG_MOVE_FEATHER_FALL_ACK"
	)
	_check(not normal_fall.is_empty() and _tail_u32(normal_fall) == 0, "feather fall turns off")

	_sent.clear()
	var knocked: Array = await _command(".knockback 4 6", "CMSG_MOVE_KNOCK_BACK_ACK")
	_check(not knocked.is_empty() and knocked[0] & Player.MoveFlag.JUMPING, "a knockback jumps")
	var landed_by: int = Time.get_ticks_msec() + ACK_WAIT_MSEC
	while not "MSG_MOVE_FALL_LAND" in _sent and Time.get_ticks_msec() < landed_by:
		await get_tree().process_frame
	_check("MSG_MOVE_FALL_LAND" in _sent, "the knockback lands")

	await get_tree().create_timer(SERVER_RESOLVE_MSEC / 1000.0).timeout
	_check(_resolved.is_empty(), "the server took every ack (it re-sent %s)" % [_resolved])
	_check(session.get_state() == WowSession.STATE_IN_WORLD, "the player is still in the world")
	_finish("")


func _command(command: String, ack: String) -> Array:
	_acks.erase(ack)
	WowClient.session.send_chat(WowSession.CHAT_SAY, command)
	var until: int = Time.get_ticks_msec() + ACK_WAIT_MSEC
	while not _acks.has(ack) and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	_check(_acks.has(ack), "%s answers %s" % [ack, command])
	return _acks.get(ack, [])


func _tail_float(ack: Array) -> float:
	var tail: PackedByteArray = ack[1]
	return tail.decode_float(0) if tail.size() >= 4 else 0.0


func _tail_u32(ack: Array) -> int:
	var tail: PackedByteArray = ack[1]
	return tail.decode_u32(0) if tail.size() >= 4 else -1


func _on_movement_changed(
	opcode: String, _position: Vector3, _orientation: float, flags: int,
	_fall_time_msec: int, _jump_velocity: Vector3, ack_counter: int, ack_tail: PackedByteArray,
) -> void:
	_sent.append(opcode)
	if ack_counter >= 0:
		_acks[opcode] = [flags, ack_tail]


func _on_object_moved(guid: int, movement: Dictionary) -> void:
	if guid == _me and movement.has("opcode"):
		_resolved.append(movement["opcode"])


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode.begins_with("SMSG_SPLINE_") and PacketReader.new(payload).packed_guid() == _me:
		_resolved.append(opcode)


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
	print("movement_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
