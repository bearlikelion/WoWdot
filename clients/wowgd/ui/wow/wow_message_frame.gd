@tool
class_name WowMessageFrame
extends VBoxContainer

const LINE: PackedScene = preload("res://ui/wow/message_line.tscn")
# MessageFrames fade their lines out over the last part of their display time.
const FADE_SECONDS: float = 1.0

@export var font_variation: StringName = &""
@export var display_duration: float = 10.0
@export var insert_at_top: bool = false
@export var max_lines: int = 8


func add_message(text: String, color: Color = Color.WHITE) -> void:
	var line: Label = LINE.instantiate()
	line.text = text
	line.theme_type_variation = font_variation
	line.self_modulate = color
	add_child(line)
	if insert_at_top:
		move_child(line, 0)
	while get_child_count() > max_lines:
		var oldest: Node = get_child(get_child_count() - 1 if insert_at_top else 0)
		remove_child(oldest)
		oldest.queue_free()
	var fade: Tween = line.create_tween()
	fade.tween_interval(maxf(display_duration - FADE_SECONDS, 0.0))
	fade.tween_property(line, "modulate:a", 0.0, FADE_SECONDS)
	fade.tween_callback(line.queue_free)
