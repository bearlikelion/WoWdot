class_name KeyBindingCheck
extends Node

const BINDING_FRAME: PackedScene = preload("res://game/ui/wow/key_binding_frame.tscn")
const REBOUND_ACTION: String = "toggle_sheath"
const REBOUND_KEY: Key = KEY_J

var _failures: PackedStringArray = []


# Drives the stock window: it lists the bindings this client has, and a press rebinds one.
func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	KeyBindings.apply()
	var rows: Array[Dictionary] = KeyBindings.listed()
	_check(rows.size() > 0, "Bindings.xml lists the bindings (%d rows)" % rows.size())
	var headers: int = rows.filter(func(row: Dictionary) -> bool: return row.has("header")).size()
	_check(headers > 0, "the list carries the stock headers (%d)" % headers)
	_check(
		rows.any(func(row: Dictionary) -> bool: return row.get("action", "") == "move_forward"),
		"a binding this client has is listed",
	)
	var frame: KeyBindingFrame = BINDING_FRAME.instantiate()
	add_child(frame)
	await get_tree().process_frame
	frame.show()
	await get_tree().process_frame
	var named: PackedStringArray = []
	var headed: PackedStringArray = []
	for row: int in KeyBindingFrame.ROWS:
		var description: String = _row_text(frame, row + 1, "Description")
		var header: String = _row_text(frame, row + 1, "Header")
		if not description.is_empty():
			named.append(description)
		if not header.is_empty():
			headed.append(header)
	print("  first rows: %s | headers: %s" % [
		", ".join(named.slice(0, 3)), ", ".join(headed.slice(0, 2)),
	])
	_check(named.size() > 0, "the window names the bindings")
	_check(headed.size() > 0, "and heads them as the stock frame does")
	var before: String = KeyBindings.binding_text(REBOUND_ACTION, 0)
	KeyBindings.bind(REBOUND_ACTION, 0, _press(REBOUND_KEY))
	var after: String = KeyBindings.binding_text(REBOUND_ACTION, 0)
	_check(after == "J", "a key press rebinds (%s to %s)" % [before, after])
	_check(
		InputMap.event_is_action(_press(REBOUND_KEY), REBOUND_ACTION),
		"and the action answers that key",
	)
	frame.hide()
	await get_tree().process_frame
	_check(
		KeyBindings.binding_text(REBOUND_ACTION, 0) == before,
		"closing without Okay puts the old key back",
	)
	if _failures.is_empty():
		print("key_binding_check: OK")
	else:
		for line: String in _failures:
			print("  ", line)
		print("key_binding_check: FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _press(key: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	return event


func _row_text(frame: KeyBindingFrame, row: int, part: String) -> String:
	var label: Label = frame.get_node("%%KeyBindingFrameBinding%d%s" % [row, part])
	return label.text if label.visible else ""


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)
