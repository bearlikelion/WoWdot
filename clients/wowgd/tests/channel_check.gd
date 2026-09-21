class_name ChannelCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 10000
const CHANNEL: String = "wowgdtest"
const GREETING: String = "hello channel"

var _failures: PackedStringArray = []
var _main: Main
var _lines: PackedStringArray = []


# Joining a channel, talking on it by number and leaving it again.
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
	var chat: ChatFrame = _main.world.hud().get_node("%ChatFrame1")
	var lines: Control = chat.find_child("MessageLines", true, false)
	lines.child_entered_tree.connect(func(node: Node) -> void:
		var label: RichTextLabel = node as RichTextLabel
		if label:
			_lines.append(label.get_parsed_text())
	)
	var zoned: bool = await _until(func() -> bool: return Channels.name_at(1).begins_with("General"))
	_check(zoned, "the zone's General channel is joined unasked: %s" % Channels.joined)
	chat.call("_on_text_submitted", "/join " + CHANNEL)
	var joined: bool = await _until(func() -> bool: return Channels.number_of(CHANNEL) > 0)
	_check(joined, "joining a channel adds it to the list")
	if not joined:
		return _finish("never joined the channel")
	var number: int = Channels.number_of(CHANNEL)
	_check(number > 1, "a joined channel takes a number after the zone's")
	_check(_line_with("Joined"), "joining prints its notice: %s" % _lines)

	_lines.clear()
	chat.call("_on_text_submitted", "/%d " % number + GREETING)
	var spoke: bool = await _until(func() -> bool: return _line_with(GREETING))
	_check(spoke, "a message sent by number comes back on the channel")
	if spoke:
		print("channel line: ", _lines[_lines.size() - 1])
		_check(_line_with("%d. " % number), "the line carries the channel number")

	_lines.clear()
	chat.open()
	var edit_box: LineEdit = chat.get_node("%ChatFrameEditBox")
	for typed: String in ["/%d " % number, "typed on the channel"]:
		edit_box.text += typed
		edit_box.text_changed.emit(edit_box.text)
	edit_box.text_submitted.emit(edit_box.text)
	var typed_through: bool = await _until(func() -> bool: return _line_with("typed on the channel"))
	_check(typed_through, "typing the number then the message sends it: %s" % _lines)
	_lines.clear()
	chat.open()
	for typed: String in ["/s ", "typed aloud"]:
		edit_box.text += typed
		edit_box.text_changed.emit(edit_box.text)
	edit_box.text_submitted.emit(edit_box.text)
	_check(await _until(func() -> bool: return _line_with("typed aloud")), "typed /s says it")

	_lines.clear()
	chat.call("_on_text_submitted", "/chatlist %d" % number)
	_check(await _until(func() -> bool: return _line_with("[%s] " % Channels.name_at(number))),
			"/chatlist names the members: %s" % _lines)
	chat.call("_on_text_submitted", "/owner %d" % number)
	_check(await _until(func() -> bool: return _line_with("owner")),
			"/owner names the channel's owner: %s" % _lines)
	chat.call("_on_text_submitted", "/who")
	_check(await _until(func() -> bool: return _line_with("total")), "/who is answered: %s" % _lines)

	_lines.clear()
	chat.call("_on_text_submitted", "/random 10")
	_check(await _until(func() -> bool: return _line_with("(1-10)")), "/random rolls: %s" % _lines)
	chat.call("_on_text_submitted", "/raidinfo")
	_check(await _until(func() -> bool: return _line_with("saved")), "/raidinfo is answered: %s" % _lines)

	_lines.clear()
	var session: WowSession = WowClient.session
	var before: int = session.get_field(session.get_player_guid(), "PLAYER_FLAGS") & 0x02
	chat.call("_on_text_submitted", "/afk")
	var away: bool = await _until(func() -> bool:
		return session.get_field(session.get_player_guid(), "PLAYER_FLAGS") & 0x02 != before)
	_check(away, "/afk flips the AFK player flag")
	_check(await _until(func() -> bool: return _line_with("AFK")), "and says so: %s" % _lines)
	chat.call("_on_text_submitted", "/afk")

	chat.call("_on_text_submitted", "/leave %d" % number)
	var left: bool = await _until(func() -> bool: return Channels.number_of(CHANNEL) == 0)
	_check(left, "leaving by number drops the channel")
	_finish("")


func _line_with(part: String) -> bool:
	for line: String in _lines:
		if line.contains(part):
			return true
	return false


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
	print("channel_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
