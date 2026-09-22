class_name RemoteMovementCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const HOST: String = "127.0.0.1"
const PORT: int = 3724
# The runner: a bare session on the second test account (remote_movement_check.sh makes it).
const PARTNER_ACCOUNT: String = "wowgd2"
const PARTNER: String = "Dolgrim"
const STAND_OFF: float = 8.0
const RUN_SECONDS: float = 2.0
const HEARTBEAT_SECONDS: float = 0.5
# A drawn step longer than this in one frame is a teleport, which reckoning should prevent.
const MAX_FRAME_STEP: float = 1.0

var _failures: PackedStringArray = []
var _main: Main
var _partner: WowSession = WowSession.new()
var _partner_at: Vector3 = Vector3.ZERO
var _partner_in_world: bool = false


func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = HOST
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	_run.call_deferred()


func _process(_delta: float) -> void:
	_partner.poll()


# The partner runs north with the stock client's start, heartbeat and stop packets while we watch.
func _run() -> void:
	if not await _until(func() -> bool: return _main.world and _main.world.player().active):
		return _finish("never reached the world")
	if not await _log_partner_in():
		return _finish("the partner never reached the world")
	var session: WowSession = WowClient.session
	var home: Vector3 = session.get_object_position(session.get_player_guid())
	var spot: Vector3 = _partner_at + Vector3(0.0, STAND_OFF, 0.0)
	session.send_chat(WowSession.CHAT_SAY, ".go xyz %f %f %f" % [spot.x, spot.y, spot.z])
	var partner_guid: int = _partner.get_player_guid()
	var entities: Entities = _main.world.get_node("Entities")
	if not await _until(func() -> bool: return entities.unit_node(partner_guid) != null, 20000):
		return _finish("the partner never appeared")
	await _frames(60)
	var node: Node3D = entities.unit_node(partner_guid)
	var start: Vector3 = _partner_at
	_move("MSG_MOVE_START_FORWARD", start, Player.MoveFlag.FORWARD)
	var worst_step: float = 0.0
	var ran: bool = false
	var last: Vector3 = node.global_position
	var elapsed: float = 0.0
	var next_heartbeat: float = HEARTBEAT_SECONDS
	while elapsed < RUN_SECONDS:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if elapsed >= next_heartbeat:
			next_heartbeat += HEARTBEAT_SECONDS
			_move("MSG_MOVE_HEARTBEAT", _ahead(start, elapsed), Player.MoveFlag.FORWARD)
		worst_step = maxf(worst_step, node.global_position.distance_to(last))
		last = node.global_position
		var player: AnimationPlayer = node.get_node_or_null("AnimationPlayer")
		ran = ran or (player != null and player.current_animation == "Run")
	var stop: Vector3 = _ahead(start, RUN_SECONDS)
	_move("MSG_MOVE_STOP", stop, Player.MoveFlag.NONE)
	await _frames(60)
	var drawn: Vector3 = WowCoords.from_godot(node.global_position)
	var off_by: float = Vector2(drawn.x - stop.x, drawn.y - stop.y).length()
	print("worst frame step %.2f yd, run clip %s, rests %.2f yd from the stop" % [
		worst_step, ran, off_by,
	])
	_check(worst_step < MAX_FRAME_STEP, "the runner moves smoothly between packets")
	_check(ran, "the runner plays its run animation")
	_check(off_by < 0.5, "the runner comes to rest where it stopped")
	session.send_chat(WowSession.CHAT_SAY, ".go xyz %f %f %f" % [home.x, home.y, home.z])
	await _frames(60)
	_finish("")


func _ahead(start: Vector3, seconds: float) -> Vector3:
	return start + Vector3(Player.DEFAULT_SPEEDS[Player.SpeedKind.RUN] * seconds, 0.0, 0.0)


func _move(opcode: String, at: Vector3, flags: int) -> void:
	_partner.send_movement(opcode, at, 0.0, flags)


func _log_partner_in() -> bool:
	_partner.realms_received.connect(func(_realms: Array) -> void: _partner.select_realm(0))
	_partner.characters_received.connect(func(characters: Array) -> void:
		for character: Dictionary in characters:
			if character["name"] == PARTNER:
				_partner.enter_world(character["guid"])
	)
	_partner.world_entered.connect(func(_map: int, at: Vector3, _facing: float) -> void:
		_partner_at = at
		_partner_in_world = true
	)
	_partner.login(HOST, PORT, PARTNER_ACCOUNT, PARTNER_ACCOUNT)
	return await _until(func() -> bool: return _partner_in_world)


func _until(condition: Callable, timeout_msec: int = TIMEOUT_MSEC) -> bool:
	var give_up: int = Time.get_ticks_msec() + timeout_msec
	while not condition.call():
		if Time.get_ticks_msec() > give_up:
			return false
		await get_tree().process_frame
	return true


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
	var outcome: String = "OK" if _failures.is_empty() else "%d failed" % _failures.size()
	print("remote_movement_check: ", outcome)
	_partner.logout()
	get_tree().quit(0 if _failures.is_empty() else 1)
