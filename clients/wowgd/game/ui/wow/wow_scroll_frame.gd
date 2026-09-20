class_name WowScrollFrame
extends Control

signal scrolled(value: float)

const WHEEL_STEP: float = 20.0

var _clip: Control
var _content: Control
var _content_top: float = 0.0
# Where a FauxScrollFrame stands, since it has no content of its own to read it back from.
var _value: float = 0.0
var _bar: Range
var _up: BaseButton
var _down: BaseButton


func _ready() -> void:
	for child: Node in get_children():
		if child is Range:
			_bar = child
		elif child is Control and (child as Control).clip_contents:
			_clip = child
	# A FauxScrollFrame has no content to slide: its owner draws the rows from the scroll value.
	if _clip and _clip.get_child_count() > 0:
		_content = _clip.get_child(0)
		_content_top = _content.position.y
	if _bar:
		var buttons: Array[Node] = _bar.get_children().filter(
			func(node: Node) -> bool: return node is BaseButton
		)
		if buttons.size() == 2:
			_up = buttons[0]
			_down = buttons[1]
			_up.pressed.connect(func() -> void: scroll_to(scroll() - _page()))
			_down.pressed.connect(func() -> void: scroll_to(scroll() + _page()))
		_bar.value_changed.connect(func(value: float) -> void: scroll_to(_bar.max_value - value))
	refresh()


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		scroll_to(scroll() - _step())
		accept_event()
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		scroll_to(scroll() + _step())
		accept_event()


# A FauxScrollFrame counts rows rather than pixels, so it moves one row at a time.
func _step() -> float:
	return WHEEL_STEP if _content else 1.0


func _page() -> float:
	return _bar.size.y / 2.0 if _content else 1.0


# Text grows its labels a frame after it is set, so the range is measured deferred.
func refresh(keep_scroll: bool = false) -> void:
	_measure.call_deferred(keep_scroll)


func scroll() -> float:
	return _content_top - _content.position.y if _content else _value


# FauxScrollFrame_Update: when the owner draws the rows itself, the range comes from the owner.
func set_range(max_scroll: float) -> void:
	if _bar:
		_bar.max_value = max_scroll
		scroll_to(scroll())


func scroll_to(value: float) -> void:
	if _bar == null:
		return
	value = clampf(value, 0.0, _bar.max_value)
	_value = value
	if _content:
		_content.position.y = _content_top - value
	# Godot's VSlider has its minimum at the bottom.
	_bar.set_value_no_signal(_bar.max_value - value)
	if _up:
		_up.disabled = value <= 0.0
		_down.disabled = value >= _bar.max_value
	scrolled.emit(value)


func _measure(keep_scroll: bool) -> void:
	if _content == null or _bar == null:
		return
	var bottom: float = _content.size.y
	for child: Node in _content.get_children():
		var control: Control = child as Control
		if control and control.visible:
			bottom = maxf(bottom, control.position.y + control.size.y)
	_bar.max_value = maxf(bottom + _content_top - _clip.size.y, 0.0)
	scroll_to(scroll() if keep_scroll else 0.0)
