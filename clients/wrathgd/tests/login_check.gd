class_name LoginCheck
extends Node

const STEP_TIMEOUT_MSEC: int = 60000
const REALMLIST: String = "127.0.0.1"
const AUTH_PORT: int = 3725
const ACCOUNT: String = "wowgd"
const PASSWORD: String = "wowgd"
# Only the WotLK Map.dbc names this one, and it lives in the locale folder's archive.
const NORTHREND: int = 571

var _session: WowSession = WowSession.new()
var _realms: Array = []
var _characters: Array = []
var _enumerated: bool = false
var _failures: PackedStringArray = []


func _ready() -> void:
	_session.realms_received.connect(_on_realms_received)
	_session.characters_received.connect(_on_characters_received)
	_run.call_deferred()


func _process(_delta: float) -> void:
	_session.poll()


func _run() -> void:
	_check_archives()
	_session.login(REALMLIST, AUTH_PORT, ACCOUNT, PASSWORD)
	if not await _until(func() -> bool: return not _realms.is_empty(),
			"the realm list arrives"):
		return _finish()
	print("realm: %s at %s" % [_realms[0]["name"], _realms[0]["address"]])
	_session.select_realm(0)
	if not await _until(
			func() -> bool: return _session.get_state() == WowSession.STATE_CHARACTER_LIST,
			"the world server takes the session"):
		return _finish()
	_session.request_characters()
	if not await _until(func() -> bool: return _enumerated, "the character list arrives"):
		return _finish()
	print("characters: %d" % _characters.size())
	_finish()


func _check_archives() -> void:
	var archive: WowArchive = WowLoader.get_shared().get_archive()
	var maps: WowDBC = WowDBC.open(archive, "Map")
	if maps == null:
		_failures.append("Map.dbc reads out of the archives")
		return
	var row: int = maps.find(NORTHREND)
	_check(row >= 0 and maps.get_string(row, "InternalName") == "Northrend",
			"Map.dbc names Northrend")


func _on_realms_received(realms: Array) -> void:
	_realms = realms


func _on_characters_received(characters: Array) -> void:
	_characters = characters
	_enumerated = true


func _until(condition: Callable, what: String) -> bool:
	var give_up: int = Time.get_ticks_msec() + STEP_TIMEOUT_MSEC
	while not condition.call():
		if _session.get_state() == WowSession.STATE_FAILED:
			_failures.append("%s (session failed)" % what)
			return false
		if Time.get_ticks_msec() > give_up:
			_failures.append(what)
			return false
		await get_tree().process_frame
	return true


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)


func _finish() -> void:
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("login_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
