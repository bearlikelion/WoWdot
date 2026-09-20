class_name InterfaceOptionsCheck
extends Node

const OPTIONS_FRAME: PackedScene = preload("res://game/ui/wow/ui_options_frame.tscn")
# Show Buff Durations and one this client does not answer yet.
const HONOURED: int = 39
const UNANSWERED: int = 28

var _failures: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: InterfaceSettings = WowAssets.interface
	settings.restore_defaults()
	var frame: UIOptionsFrame = OPTIONS_FRAME.instantiate()
	add_child(frame)
	await get_tree().process_frame
	frame.show()
	await get_tree().process_frame
	var honoured: WowButton = frame.get_node("%%UIOptionsFrameCheckButton%d" % HONOURED)
	var unanswered: WowButton = frame.get_node("%%UIOptionsFrameCheckButton%d" % UNANSWERED)
	_check(not honoured.disabled, "an option this client answers can be ticked")
	_check(unanswered.disabled, "an option it does not answer is greyed out")
	_check(
		_label(frame, HONOURED) == WowStrings.get_text("SHOW_BUFF_DURATION_TEXT"),
		"the stock string names the option (%s)" % _label(frame, HONOURED),
	)
	_check(honoured.checked, "the box shows what the setting stands at")
	honoured.pressed.emit()
	await get_tree().process_frame
	_check(not settings.is_on(&"show_buff_durations"), "ticking a box moves the setting")
	_check(not honoured.checked, "and the box follows it")
	frame.hide()
	await get_tree().process_frame
	_check(settings.is_on(&"show_buff_durations"), "closing without Okay puts it back")
	if _failures.is_empty():
		print("interface_options_check: OK")
	else:
		for line: String in _failures:
			print("  ", line)
		print("interface_options_check: FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _label(frame: UIOptionsFrame, number: int) -> String:
	var check: Control = frame.get_node("%%UIOptionsFrameCheckButton%d" % number)
	return (check.get_node("UIOptionsFrameCheckButton%dText" % number) as Label).text


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)
