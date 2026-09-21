class_name GameObjectCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 10000
# A chair in the Lion's Pride Inn, which seats whoever uses it.
const CHAIR_ENTRY: int = 22803
const CHAIR_AT: Vector3 = Vector3(-9458.4, 16.0574, 56.9748)
# UNIT_STAND_STATE_SIT_LOW_CHAIR through SIT_HIGH_CHAIR.
const CHAIR_STATES: Array[int] = [4, 5, 6]
const STAND_STATE_STAND: int = 0

var _failures: PackedStringArray = []
var _main: Main


# Uses a game object and checks the server answered, which nothing but a mailbox could do before.
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
	await _teleport(CHAIR_AT)
	var chair: int = _object_with_entry(CHAIR_ENTRY)
	if chair == 0:
		return _finish("no chair in the Lion's Pride Inn")
	# The first use only asks what the object is; the answer has to bring the click back.
	_main.world._use_game_object(chair)
	var seated: bool = await _until(func() -> bool: return _stand_state() in CHAIR_STATES)
	print("stand state after using the chair: ", _stand_state())
	_check(seated, "using a chair seats the player")
	_check(
		WowClient.session.get_state() == WowSession.STATE_IN_WORLD, "the server kept the session"
	)
	WowClient.session.send_chat(WowSession.CHAT_SAY, ".modify standstate 0")
	await _until(func() -> bool: return _stand_state() == STAND_STATE_STAND)
	_finish("")


func _stand_state() -> int:
	var session: WowSession = WowClient.session
	return session.get_field(session.get_player_guid(), "UNIT_FIELD_BYTES_1") & 0xFF


func _object_with_entry(entry: int) -> int:
	var session: WowSession = WowClient.session
	for guid: int in session.get_object_guids():
		if session.get_field(guid, "OBJECT_FIELD_ENTRY") == entry:
			return guid
	return 0


func _teleport(wow_position: Vector3) -> void:
	WowClient.session.send_chat(
		WowSession.CHAT_SAY, ".go xyz %f %f %f" % [wow_position.x, wow_position.y, wow_position.z]
	)
	await _frames(30)
	var loaded_by: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while not _main.world.player().active and Time.get_ticks_msec() < loaded_by:
		await get_tree().process_frame
	await _frames(60)


func _until(condition: Callable) -> bool:
	var until: int = Time.get_ticks_msec() + STEP_MSEC
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
	print("gameobject_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
