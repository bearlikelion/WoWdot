class_name ChaseCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 150000
const TYPE_UNIT: int = 3
const CRITTER_HEALTH: int = 30
# Where to stand before pulling, and the range a creature has to reach to swing.
const PULL_RANGE: float = 5.0
const MELEE_RANGE: float = 5.0
const WATCH_SECONDS: float = 8.0
# How long to run away, and how far behind the creature may be when the player stops.
const RUN_SECONDS: int = 5
const CHASE_RANGE: float = 12.0

var _failures: PackedStringArray = []
var _main: Main
var _swings: int = 0


# Pulls a creature and watches whether it closes to melee and stays there.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = "127.0.0.1"
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var give_up: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _main.world == null or not _main.world.player().active:
		if Time.get_ticks_msec() > give_up:
			return _finish("never reached the world")
		await get_tree().process_frame
	await _frames(120)
	var session: WowSession = WowClient.session
	session.melee_swing.connect(
		func(_attacker: int, _victim: int, _damage: int, _info: int, _state: int) -> void:
			_swings += 1
	)
	session.send_chat(WowSession.CHAT_SAY, ".modify hp 5000")
	await _frames(30)
	var prey: int = 0
	for hop: int in 4:
		prey = _nearest_prey()
		if prey == 0:
			await _frames(60)
			continue
		if _yards_to(prey) <= PULL_RANGE:
			break
		await _go(session.get_object_position(prey) + Vector3(3.0, 0.0, 0.0))
	if prey == 0 or _yards_to(prey) > PULL_RANGE:
		return _finish("no creature came within %d yards" % PULL_RANGE)
	print("pulling %s from %.1f yards" % [session.get_object_name(prey), _yards_to(prey)])
	_main.world.select(prey)
	await _frames(20)
	session.attack_swing_error.connect(func(reason: int) -> void:
		print("  swing refused: %d" % reason)
	)
	_main.world.call("_face", prey)
	await _frames(10)
	session.attack(prey)
	var closest: float = INF
	var samples: PackedStringArray = []
	var started: int = Time.get_ticks_msec()
	var last: int = 0
	while Time.get_ticks_msec() - started < int(WATCH_SECONDS * 1000.0):
		if session.get_field(prey, "UNIT_FIELD_HEALTH") == 0:
			break
		var gap: float = _yards_to(prey)
		closest = minf(closest, gap)
		var second: int = (Time.get_ticks_msec() - started) / 1000
		if second != last:
			last = second
			samples.append("%ds %.1fy" % [second, gap])
		await get_tree().process_frame
	print("  standing: ", " ".join(samples))
	print("  closest %.1f yards, swings %d" % [closest, _swings])
	_check(closest <= MELEE_RANGE, "the creature closed to melee (%.1f yards)" % closest)
	_check(_swings > 0, "blows were traded")
	if session.get_field(prey, "UNIT_FIELD_HEALTH") == 0:
		return _finish("")
	# Running off is where the server's idea of the player has to keep up with the client's.
	session.stop_attack()
	await _seconds(1.0)
	var fled: PackedStringArray = []
	var swung: int = _swings
	Input.action_press("move_forward")
	for second: int in RUN_SECONDS:
		await _seconds(1.0)
		fled.append("%ds %.1fy" % [second + 1, _yards_to(prey)])
	Input.action_release("move_forward")
	await _seconds(3.0)
	var caught: float = _yards_to(prey)
	print("  running: %s, then %.1f yards, %d more swings" % [
		" ".join(fled), caught, _swings - swung,
	])
	_check(caught <= CHASE_RANGE, "the creature kept up with a running player (%.1f yards)" % caught)
	_finish("")


func _nearest_prey() -> int:
	var session: WowSession = WowClient.session
	var player: int = session.get_player_guid()
	var here: Vector3 = session.get_object_position(player)
	var nearest: int = 0
	var best: float = INF
	for guid: int in session.get_object_guids():
		if session.get_object_type(guid) != TYPE_UNIT \
		or session.get_field(guid, "UNIT_FIELD_HEALTH") == 0 \
		or session.get_field(guid, "UNIT_FIELD_MAXHEALTH") < CRITTER_HEALTH:
			continue
		if UnitReaction.between(session, player, guid) == UnitReaction.Reaction.FRIENDLY \
		or session.get_field(guid, "UNIT_NPC_FLAGS") != 0:
			continue
		var distance: float = session.get_object_position(guid).distance_to(here)
		if distance < best:
			best = distance
			nearest = guid
	return nearest


func _yards_to(guid: int) -> float:
	var here: Vector3 = WowCoords.from_godot(_main.world.player().global_position)
	return here.distance_to(WowClient.session.get_object_position(guid))


func _go(spot: Vector3) -> void:
	WowClient.session.send_chat(
		WowSession.CHAT_SAY, ".go xyz %f %f %f" % [spot.x, spot.y, spot.z]
	)
	await _frames(150)


func _seconds(count: float) -> void:
	await get_tree().create_timer(count).timeout


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
	print("chase_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
