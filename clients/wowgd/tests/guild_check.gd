class_name GuildCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 15000
const GUILD_NAME: String = "WoWdot Testers"
const MOTD: String = "Checked by guild_check at %d"

var _failures: PackedStringArray = []
var _main: Main
var _lines: PackedStringArray = []


# Makes a guild with a GM command, then reads it back through the guild tab.
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
	var player_name: String = session.get_object_name(session.get_player_guid())
	var hud: Hud = _main.world.hud()
	var friends: FriendsFrame = hud.find_child("FriendsFrame", true, false)
	friends.message_added.connect(func(text: String) -> void: _lines.append(text))
	session.send_chat(WowSession.CHAT_SAY, '.guild create %s "%s"' % [player_name, GUILD_NAME])
	await _frames(60)
	hud.find_child("MainMenuBar", true, false).panel_toggled.emit(
		MainMenuBar.GamePanel.SOCIAL
	)
	friends.show_tab(FriendsFrame.Tab.GUILD)
	await _frames(20)
	_check(friends.get_node("%GuildFrame").visible, "the guild tab shows the guild window")
	var listed: bool = await _until(func() -> bool: return _row_named(friends, player_name) >= 0)
	_check(listed, "the roster lists the player")
	_check(
		await _until(func() -> bool:
			return (friends.get_node("%FriendsFrameTitleText") as Label).text == GUILD_NAME),
		"the window is titled with the guild's name",
	)
	if listed:
		var row: int = _row_named(friends, player_name)
		var level: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_LEVEL")
		_check(
			_row_text(friends, row, "Level") == str(level), "the roster row has the player's level"
		)
		_check(not _row_text(friends, row, "Class").is_empty(), "the roster row names the class")
	var motd: String = MOTD % Time.get_unix_time_from_system()
	FriendsFrame.send_command("CMSG_GUILD_MOTD", motd)
	_check(
		await _until(func() -> bool:
			return (friends.get_node("%GuildFrameNotesText") as Label).text == motd),
		"the message of the day arrives with the roster",
	)
	_check(
		await _until(func() -> bool: return _heard(motd)),
		"the message of the day is announced in chat",
	)
	_finish("")


func _heard(text: String) -> bool:
	for line: String in _lines:
		if line.contains(text):
			return true
	return false


func _row_text(friends: FriendsFrame, index: int, column: String) -> String:
	return (friends.get_node("%%GuildFrameButton%d%s" % [index + 1, column]) as Label).text


func _row_named(friends: FriendsFrame, player_name: String) -> int:
	for i: int in FriendsFrame.GUILD_ROWS:
		var row: Control = friends.get_node("%%GuildFrameButton%d" % (i + 1))
		if row.visible and _row_text(friends, i, "Name") == player_name:
			return i
	return -1


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
	print("guild_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
