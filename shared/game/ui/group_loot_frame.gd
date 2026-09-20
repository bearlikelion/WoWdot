@tool
class_name GroupLootFrame
extends Control

signal rolled(roll: Roll)

# CMSG_LOOT_ROLL's roll types.
enum Roll { PASS, NEED, GREED }

var _seconds_left: float = 0.0
var _seconds_total: float = 1.0

@onready var _timer_bar: Control = %Timer


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	%RollButton.pressed.connect(_on_pressed.bind(Roll.NEED))
	%GreedButton.pressed.connect(_on_pressed.bind(Roll.GREED))
	%PassButton.pressed.connect(_on_pressed.bind(Roll.PASS))
	set_process(false)


func _process(delta: float) -> void:
	_seconds_left -= delta
	_timer_bar.scale.x = clampf(_seconds_left / _seconds_total, 0.0, 1.0)
	if _seconds_left <= 0.0:
		set_process(false)
		queue_free()


# GroupLootFrame_OpenNewFrame: the item on offer and how long there is to answer.
func show_roll(item_entry: int, seconds: float) -> void:
	(%Icon as TextureRect).texture = Inventory.icon(item_entry)
	(%Name as Label).text = WowClient.session.get_item_info(item_entry).get("name", "")
	_seconds_total = maxf(seconds, 0.001)
	_seconds_left = _seconds_total
	set_process(true)
	show()


func _on_pressed(roll: Roll) -> void:
	rolled.emit(roll)
	queue_free()
