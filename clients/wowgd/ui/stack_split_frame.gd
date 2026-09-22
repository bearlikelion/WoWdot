class_name StackSplitFrame
extends Control

signal accepted(count: int)

var _count: int = 1
var _stack: int = 1
# Digits typed so far, so that "1" then "2" reads as twelve rather than two.
var _typed: int = 0


func _ready() -> void:
	# An unanchored texture fills its frame in WoW, whatever Size the XML gives it.
	($Texture as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	%StackSplitLeftButton.pressed.connect(_step.bind(-1))
	%StackSplitRightButton.pressed.connect(_step.bind(1))
	%StackSplitOkayButton.pressed.connect(_accept)
	%StackSplitCancelButton.pressed.connect(hide)
	hide()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if not visible or key == null or not key.pressed:
		return
	get_viewport().set_input_as_handled()
	var digit: int = key.unicode - KEY_0
	if digit >= 0 and digit <= 9:
		_typed = _typed * 10 + digit
		_show_count(_typed)
	elif key.keycode == KEY_BACKSPACE:
		@warning_ignore("integer_division")
		_typed = _typed / 10
		_show_count(_typed)
	elif key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_accept()
	elif key.keycode == KEY_ESCAPE:
		hide()
	elif key.keycode in [KEY_LEFT, KEY_DOWN]:
		_step(-1)
	elif key.keycode in [KEY_RIGHT, KEY_UP]:
		_step(1)


# Splitting takes at least one and leaves at least one behind.
func open(stack: int, at: Vector2) -> void:
	_stack = stack
	_typed = 0
	_show_count(1)
	global_position = at - Vector2(size.x / 2.0, size.y)
	show()


func _step(by: int) -> void:
	_typed = 0
	_show_count(_count + by)


func _show_count(count: int) -> void:
	_count = clampi(count, 1, _stack - 1)
	%StackSplitText.text = str(_count)
	(%StackSplitLeftButton as BaseButton).disabled = _count <= 1
	(%StackSplitRightButton as BaseButton).disabled = _count >= _stack - 1


func _accept() -> void:
	hide()
	accepted.emit(_count)
