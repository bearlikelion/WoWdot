class_name WowScrollFrame
extends Control

const WHEEL_STEP: float = 20.0

var _clip: Control
var _content: Control
var _content_top: float = 0.0
var _bar: Range
var _up: BaseButton
var _down: BaseButton


func _ready() -> void:
	for child: Node in get_children():
		if child is Range:
			_bar = child
		elif child is Control and (child as Control).clip_contents:
			_clip = child
	if _clip == null or _clip.get_child_count() == 0:
		return
	_content = _clip.get_child(0)
	_content_top = _content.position.y
	if _bar:
		var buttons: Array[Node] = _bar.get_children().filter(
			func(node: Node) -> bool: return node is BaseButton
		)
		if buttons.size() == 2:
			_up = buttons[0]
			_down = buttons[1]
			_up.pressed.connect(func() -> void: scroll_to(scroll() - _bar.size.y / 2.0))
			_down.pressed.connect(func() -> void: scroll_to(scroll() + _bar.size.y / 2.0))
		_bar.value_changed.connect(func(value: float) -> void: scroll_to(_bar.max_value - value))
	refresh()


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		scroll_to(scroll() - WHEEL_STEP)
		accept_event()
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		scroll_to(scroll() + WHEEL_STEP)
		accept_event()


# Text grows its labels a frame after it is set, so the range is measured deferred.
func refresh() -> void:
	_measure.call_deferred()


func scroll() -> float:
	return _content_top - _content.position.y if _content else 0.0


func scroll_to(value: float) -> void:
	if _content == null or _bar == null:
		return
	value = clampf(value, 0.0, _bar.max_value)
	_content.position.y = _content_top - value
	# Godot's VSlider has its minimum at the bottom.
	_bar.set_value_no_signal(_bar.max_value - value)
	if _up:
		_up.disabled = value <= 0.0
		_down.disabled = value >= _bar.max_value


func _measure() -> void:
	if _content == null or _bar == null:
		return
	var bottom: float = _content.size.y
	for child: Node in _content.get_children():
		var control: Control = child as Control
		if control and control.visible:
			bottom = maxf(bottom, control.position.y + control.size.y)
	_bar.max_value = maxf(bottom + _content_top - _clip.size.y, 0.0)
	scroll_to(0.0)
