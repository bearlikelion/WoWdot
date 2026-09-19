class_name ThrowawayCharacter
extends SceneTree

# Makes or removes a test character: -- --create=Name or -- --delete=Name.
const HOST: String = "127.0.0.1"
const PORT: int = 3724
const ACCOUNT: String = "wowgd"
const PASSWORD: String = "wowgd"
const DWARF: int = 3
const WARRIOR: int = 1
const TIMEOUT_MSEC: int = 20000

var _session: WowSession = WowSession.new()
var _realms: Array = []
var _characters: Array = []
var _fresh: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	_session.realms_received.connect(func(list: Array) -> void: _realms = list)
	_session.characters_received.connect(func(list: Array) -> void:
		_characters = list
		_fresh = true
	)
	_session.login(HOST, PORT, ACCOUNT, PASSWORD)
	if not await _until(func() -> bool: return not _realms.is_empty()):
		return _done("no realm list")
	_session.select_realm(0)
	if not await _until(func() -> bool: return _fresh):
		return _done("no character list")
	if args.has("create") and not _names().has(args["create"]):
		_fresh = false
		_session.character_created.connect(
			func(_ok: bool, _code: int) -> void: _session.request_characters(), CONNECT_ONE_SHOT
		)
		_session.create_character({
			"name": args["create"], "race": DWARF, "class": WARRIOR, "gender": 0,
		})
		await _until(func() -> bool: return _fresh)
		return _done("" if _names().has(args["create"]) else "could not create " + args["create"])
	if args.has("delete"):
		for character: Dictionary in _characters:
			if character["name"] == args["delete"]:
				_fresh = false
				_session.character_deleted.connect(
					func(_ok: bool, _code: int) -> void: _session.request_characters(),
					CONNECT_ONE_SHOT,
				)
				_session.delete_character(character["guid"])
				await _until(func() -> bool: return _fresh)
	_done("")


func _names() -> PackedStringArray:
	var names: PackedStringArray = []
	for character: Dictionary in _characters:
		names.append(character["name"])
	return names


func _until(condition: Callable) -> bool:
	var give_up: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while not condition.call():
		if Time.get_ticks_msec() > give_up:
			return false
		_session.poll()
		await process_frame
	return true


func _done(error: String) -> void:
	print("throwaway_character: ", "OK" if error.is_empty() else error, " ", _names())
	_session.disconnect()
	quit(0 if error.is_empty() else 1)
