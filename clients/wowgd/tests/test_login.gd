class_name TestLogin
extends SceneTree

enum ObjectType { UNIT = 3, PLAYER = 4 }

const HOST: String = "127.0.0.1"
const PORT: int = 3724
const ACCOUNT: String = "wowgd"
const PASSWORD: String = "wowgd"
const NEW_CHARACTER: Dictionary = {"name": "Tessaline", "race": 1, "class": 1, "gender": 0}
const TIMEOUT_MSEC: int = 30000
const RUN_SPEED: float = 7.0
const RUN_SECONDS: float = 2.0
const MOVE_FORWARD: int = 0x1
const MAX_SAVED_ERROR: float = 1.0
# The Northshire start; runs alternate north and south of it so repeated tests stay put.
const START_X: float = -8949.95

var _session: WowSession
var _failures: PackedStringArray = []
var _message: String = ""
var _realms: Array = []
var _characters: Array = []
var _characters_fresh: bool = false
var _entered: Dictionary = {}
var _units: int = 0
var _moves: int = 0
var _unhandled: Dictionary[String, int] = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_session = WowSession.new()
	_session.state_changed.connect(_on_state_changed)
	_session.realms_received.connect(_on_realms_received)
	_session.characters_received.connect(_on_characters_received)
	_session.world_entered.connect(_on_world_entered)
	_session.object_created.connect(_on_object_created)
	_session.object_moved.connect(_on_object_moved)
	_session.packet_received.connect(_on_packet_received)
	_session.login(HOST, PORT, ACCOUNT, PASSWORD)

	if not _check(await _until(func() -> bool: return not _realms.is_empty()), "realm list"):
		return _finish()
	print("realms: ", _realms)
	_session.select_realm(0)
	if not _check(await _until(func() -> bool: return _characters_fresh), "character list"):
		return _finish()
	if _characters.is_empty():
		_characters_fresh = false
		_session.create_character(NEW_CHARACTER)
		_session.character_created.connect(_on_character_created, CONNECT_ONE_SHOT)
		var created: bool = await _until(func() -> bool: return _characters_fresh)
		if not _check(created and not _characters.is_empty(), "character created"):
			return _finish()
	var character: Dictionary = _characters[0]
	print("entering as %s, level %d, race %d, class %d" % [
		character["name"], character["level"], character["race"], character["class"],
	])

	_session.enter_world(character["guid"])
	if not _check(await _until(func() -> bool: return not _entered.is_empty()), "world entered"):
		return _finish()
	print("in world: ", _entered)
	await _wait(3.0)
	print("objects in view: %d creatures, %d total" % [_units, _session.get_object_guids().size()])
	_check(_units >= 3, "nearby creatures arrive")
	print("creature moves in 3 s: %d" % _moves)
	_check(_moves > 0, "creature movement arrives")
	print("opcodes left to GDScript: ", _unhandled)
	var player_health: int = _session.get_field(_session.get_player_guid(), "UNIT_FIELD_HEALTH")
	_check(player_health > 0, "player health field is readable (%d)" % player_health)

	var start: Vector3 = _entered["position"]
	var facing: float = 0.0 if start.x <= START_X else PI
	var end: Vector3 = start + Vector3(cos(facing), sin(facing), 0.0) * RUN_SPEED * RUN_SECONDS
	_session.send_movement("MSG_MOVE_START_FORWARD", start, facing, MOVE_FORWARD)
	await _wait(RUN_SECONDS)
	_session.send_movement("MSG_MOVE_STOP", end, facing, 0)
	await _wait(0.5)

	_session.logout()
	var logged_out: bool = await _until(
		func() -> bool: return _session.get_state() == WowSession.STATE_CHARACTER_LIST
	)
	if not _check(logged_out, "logout completes"):
		return _finish()
	_characters_fresh = false
	_session.request_characters()
	if not _check(await _until(func() -> bool: return _characters_fresh), "character list again"):
		return _finish()
	for saved: Dictionary in _characters:
		if saved["guid"] == character["guid"]:
			var off: float = (saved["position"] as Vector3).distance_to(end)
			print("server saved %s, expected %s" % [saved["position"], end])
			_check(off < MAX_SAVED_ERROR, "server saved the walked-to position (%.2f yd off)" % off)
	_finish()


func _until(condition: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		_session.poll()
		if condition.call():
			return true
		if _session.get_state() == WowSession.STATE_FAILED:
			return false
		await process_frame
	return false


func _wait(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		_session.poll()
		await process_frame


func _on_state_changed(state: int, message: String) -> void:
	if not message.is_empty():
		_message = message
	print("state ", state, " ", message)


func _on_realms_received(realms: Array) -> void:
	_realms = realms


func _on_characters_received(characters: Array) -> void:
	_characters = characters
	_characters_fresh = true


func _on_character_created(success: bool, code: int) -> void:
	_check(success, "character creation accepted (code %d)" % code)
	_session.request_characters()


func _on_world_entered(map_id: int, position: Vector3, orientation: float) -> void:
	_entered = {"map": map_id, "position": position, "orientation": orientation}


func _on_object_created(guid: int, type_id: int) -> void:
	if type_id == ObjectType.UNIT:
		_units += 1


func _on_object_moved(guid: int, movement: Dictionary) -> void:
	if guid != _session.get_player_guid():
		_moves += 1


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	_unhandled[opcode] = _unhandled.get(opcode, 0) + 1


func _check(condition: bool, what: String) -> bool:
	if not condition:
		_failures.append(what + ("" if _message.is_empty() else " (" + _message + ")"))
	return condition


func _finish() -> void:
	_session.disconnect()
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("test_login: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
