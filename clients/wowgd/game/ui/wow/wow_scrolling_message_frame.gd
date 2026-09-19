@tool
class_name WowScrollingMessageFrame
extends Control

const LINE: PackedScene = preload("res://game/ui/wow/message_line.tscn")
# ScrollingMessageFrames fade a line out over this long once its display time is up.
const FADE_SECONDS: float = 3.0

@export var font_variation: StringName = &""
@export var display_duration: float = 120.0
@export var max_lines: int = 128

# How many of the newest lines are scrolled out of view below.
var _scrolled: int = 0

@onready var _lines: VBoxContainer = %MessageLines


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	for line: Label in _lines.get_children():
		var age: float = now - float(line.get_meta(&"added", now))
		line.modulate.a = 1.0 if _scrolled > 0 else clampf(
			(display_duration + FADE_SECONDS - age) / FADE_SECONDS, 0.0, 1.0
		)


func add_message(text: String, color: Color = Color.WHITE) -> void:
	var line: Label = LINE.instantiate()
	line.text = text
	line.theme_type_variation = font_variation
	line.self_modulate = color
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.set_meta(&"added", Time.get_ticks_msec() / 1000.0)
	_lines.add_child(line)
	while _lines.get_child_count() > max_lines:
		var oldest: Node = _lines.get_child(0)
		_lines.remove_child(oldest)
		oldest.queue_free()
	if _scrolled > 0:
		_scrolled += 1
	_apply_scroll()


func scroll_up() -> void:
	_scrolled = mini(_scrolled + 1, maxi(_lines.get_child_count() - 1, 0))
	_apply_scroll()


func scroll_down() -> void:
	_scrolled = maxi(_scrolled - 1, 0)
	_apply_scroll()


func scroll_to_bottom() -> void:
	_scrolled = 0
	_apply_scroll()


func at_bottom() -> bool:
	return _scrolled == 0


func all_text() -> String:
	var lines: PackedStringArray = []
	for line: Label in _lines.get_children():
		lines.append(line.text)
	return "\n".join(lines)


# The list is bottom-aligned, so hiding the newest lines brings older ones into view.
func _apply_scroll() -> void:
	var count: int = _lines.get_child_count()
	for i: int in count:
		(_lines.get_child(i) as Label).visible = i < count - _scrolled
