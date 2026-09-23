class_name TutorialFrame
extends Control

const ALERT: PackedScene = preload("res://ui/tutorial_alert_button.tscn")
# 3.3.5 shows one alert button, not the row 1.12 queues up.
const MAX_ALERTS: int = 1
const ALERT_SPACING: float = 36.0
# TutorialFrameParent sits this far above the bottom of the screen.
const ALERT_BOTTOM: float = 55.0
const ALERT_SIZE: Vector2 = Vector2(116.0, 71.0)
# TutorialFrame_Update: the text's height plus the title, button and border.
const FRAME_PADDING: float = 62.0
const PULSE_SECONDS: float = 10.0
const PULSE_HALF_PERIOD: float = 0.5

# Alert buttons are added here, so they stay clickable while this frame is hidden.
@export var alerts: Control

@onready var _title: Label = %TutorialFrameTitle
@onready var _text: Label = %TutorialFrameText
@onready var _okay: BaseButton = %TutorialFrameOkayButton


func _ready() -> void:
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_okay.pressed.connect(hide)
	WowClient.tutorials.queue_changed.connect(_update_alerts)
	_update_alerts()


func _update_alerts() -> void:
	for button: Node in alerts.get_children():
		button.queue_free()
	var queue: Array[Tutorials.Id] = WowClient.tutorials.queue
	for i: int in mini(queue.size(), MAX_ALERTS):
		var button: WowButton = ALERT.instantiate()
		alerts.add_child(button)
		button.show()
		button.offset_left = -ALERT_SIZE.x / 2.0 + ALERT_SPACING * i
		button.offset_right = button.offset_left + ALERT_SIZE.x
		button.offset_bottom = -ALERT_BOTTOM
		button.offset_top = -ALERT_BOTTOM - ALERT_SIZE.y
		button.pressed.connect(_open.bind(queue[i]))
		button.mouse_entered.connect(_on_alert_hovered.bind(button, queue[i]))
		button.mouse_exited.connect(_on_alert_left.bind(button))
		_pulse(button)


func _pulse(button: WowButton) -> void:
	var pulse: Tween = button.create_tween().set_loops(int(PULSE_SECONDS / PULSE_HALF_PERIOD / 2.0))
	pulse.tween_property(button, ^"modulate:a", 0.0, PULSE_HALF_PERIOD)
	pulse.tween_property(button, ^"modulate:a", 1.0, PULSE_HALF_PERIOD)


func _open(id: Tutorials.Id) -> void:
	_title.text = WowStrings.get_text("TUTORIAL_TITLE%d" % (id + 1))
	_text.text = WowStrings.get_text("TUTORIAL%d" % (id + 1))
	WowClient.tutorials.acknowledge(id)
	show()
	_fit.call_deferred()


# Deferred so the label has wrapped its new text before its height is read.
func _fit() -> void:
	_text.size.y = _text.get_minimum_size().y
	offset_top = offset_bottom - _text.size.y - FRAME_PADDING


func _on_alert_hovered(button: WowButton, id: Tutorials.Id) -> void:
	if GameTooltip.current:
		GameTooltip.current.set_text(button, WowStrings.get_text("TUTORIAL_TITLE%d" % (id + 1)))


func _on_alert_left(button: WowButton) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(button)
