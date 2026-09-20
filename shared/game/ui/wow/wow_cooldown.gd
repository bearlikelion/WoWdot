@tool
class_name WowCooldown
extends Control

const SHADE: Color = Color(0.0, 0.0, 0.0, 0.65)
const SWEEP_POINTS: int = 32

var _start_msec: int = 0
var _duration_msec: int = 0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true
	set_process(false)


func _process(_delta: float) -> void:
	if _remaining() <= 0.0:
		stop()
	queue_redraw()


# A zero duration clears the sweep, like CooldownFrame_SetTimer.
func start(start_msec: int, duration_msec: int) -> void:
	_start_msec = start_msec
	_duration_msec = duration_msec
	visible = duration_msec > 0
	set_process(visible)
	queue_redraw()


func stop() -> void:
	_duration_msec = 0
	visible = false
	set_process(false)


func _remaining() -> float:
	if _duration_msec <= 0:
		return 0.0
	var elapsed: int = Time.get_ticks_msec() - _start_msec
	return clampf(1.0 - float(elapsed) / _duration_msec, 0.0, 1.0)


# The shaded part is what is left, sweeping clockwise from twelve o'clock.
func _draw() -> void:
	var left: float = _remaining()
	if left <= 0.0:
		return
	var center: Vector2 = size / 2.0
	var radius: float = size.length()
	var points: PackedVector2Array = [center]
	var start_angle: float = -PI / 2.0 + TAU * (1.0 - left)
	for i: int in SWEEP_POINTS + 1:
		var angle: float = start_angle + TAU * left * i / SWEEP_POINTS
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, SHADE)
