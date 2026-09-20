class_name EmoteCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 10000
const DANCE: String = "/dance"
const WAVE_TOKEN: String = "WAVE"

var _failures: PackedStringArray = []
var _main: Main
var _lines: PackedStringArray = []


# A slash emote reaches the server, comes back as a chat line and plays its animation.
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
	_check(Emotes.find("dance") > 0, "a slash token finds its text emote")
	_check(Emotes.find("notanemote") == 0, "an unknown token finds none")
	_check(not Emotes.animation(Emotes.emote_of(Emotes.find(WAVE_TOKEN))).is_empty(),
		"a text emote names an animation")

	var hud: Hud = _main.world.hud()
	var chat: ChatFrame = hud.get_node("%ChatFrame1")
	var lines: Control = chat.find_child("MessageLines", true, false)
	lines.child_entered_tree.connect(func(node: Node) -> void:
		var label: RichTextLabel = node as RichTextLabel
		if label:
			_lines.append(label.get_parsed_text())
	)
	chat.call("_on_text_submitted", DANCE)
	var danced: bool = await _until(func() -> bool: return not _lines.is_empty())
	_check(danced, "the emote comes back as a chat line")
	if danced:
		print("emote line: ", _lines[0])
		_check(_lines[0].to_lower().contains("dance"), "the line reads as the emote")
	_finish("")


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
	print("emote_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
