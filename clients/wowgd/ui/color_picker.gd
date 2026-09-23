class_name WowColorPicker
extends Control

# ColorPickerFrame_OnShow: the frame is this wide with the opacity slider and this without.
const WIDTH_WITH_OPACITY: float = 365.0
const WIDTH_WITHOUT_OPACITY: float = 305.0

var _hsv: Vector3 = Vector3(0.0, 0.0, 1.0)
var _opacity: float = 1.0
var _previous: Color = Color.WHITE
var _on_change: Callable = Callable()

@onready var _wheel: Control = %ColorPickerWheel
@onready var _wheel_thumb: Control = %ColorWheelThumb
@onready var _value: Control = %ColorValue
@onready var _value_thumb: Control = %ColorValueThumb
@onready var _slider: VSlider = %OpacitySliderFrame


func _ready() -> void:
	_wheel.gui_input.connect(_on_wheel_input)
	_value.gui_input.connect(_on_value_input)
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.value_changed.connect(_on_opacity_changed)
	%ColorPickerOkayButton.pressed.connect(hide)
	%ColorPickerCancelButton.pressed.connect(_cancel)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_cancel()


# OpenColorPicker: on_change hears every change, and Cancel hands it the starting colour back.
func open(color: Color, with_opacity: bool, on_change: Callable) -> void:
	_previous = color
	_on_change = on_change
	_hsv = Vector3(color.h, color.s, color.v)
	_opacity = color.a
	_slider.visible = with_opacity
	# The slider reads opacity upside down, as the stock chat frames set it.
	_slider.set_value_no_signal(1.0 - _opacity)
	size.x = WIDTH_WITH_OPACITY if with_opacity else WIDTH_WITHOUT_OPACITY
	_redraw()
	show()


func color() -> Color:
	return Color.from_hsv(_hsv.x, _hsv.y, _hsv.z, _opacity)


func _redraw() -> void:
	(_wheel.material as ShaderMaterial).set_shader_parameter(&"value", _hsv.z)
	(_value.material as ShaderMaterial).set_shader_parameter(
		&"top_color", Color.from_hsv(_hsv.x, _hsv.y, 1.0)
	)
	var radius: float = _wheel.size.x / 2.0
	var angle: float = _hsv.x * TAU
	var at: Vector2 = Vector2(radius, radius) + Vector2(cos(angle), -sin(angle)) * _hsv.y * radius
	_wheel_thumb.position = at - _wheel_thumb.size / 2.0
	_value_thumb.position.y = (1.0 - _hsv.z) * _value.size.y - _value_thumb.size.y / 2.0
	(%ColorSwatch as ColorRect).color = Color.from_hsv(_hsv.x, _hsv.y, _hsv.z)
	if _on_change.is_valid():
		_on_change.call(color())


func _cancel() -> void:
	hide()
	if _on_change.is_valid():
		_on_change.call(_previous)


func _on_wheel_input(event: InputEvent) -> void:
	if not _dragging(event):
		return
	var radius: float = _wheel.size.x / 2.0
	var offset: Vector2 = ((event as InputEventMouse).position - Vector2(radius, radius)) / radius
	_hsv.x = fposmod(atan2(-offset.y, offset.x) / TAU, 1.0)
	_hsv.y = minf(offset.length(), 1.0)
	_redraw()


func _on_value_input(event: InputEvent) -> void:
	if _dragging(event):
		var y: float = (event as InputEventMouse).position.y
		_hsv.z = clampf(1.0 - y / _value.size.y, 0.0, 1.0)
		_redraw()


func _on_opacity_changed(value: float) -> void:
	_opacity = 1.0 - value
	_redraw()


func _dragging(event: InputEvent) -> bool:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click:
		return click.pressed and click.button_index == MOUSE_BUTTON_LEFT
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	return motion != null and motion.button_mask & MOUSE_BUTTON_MASK_LEFT != 0
