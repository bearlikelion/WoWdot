class_name ItemButton
extends WowButton

signal right_clicked

@onready var _icon: TextureRect = %IconTexture
@onready var _count: Label = %Count


func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		right_clicked.emit()


# SetItemButtonTexture and SetItemButtonCount: a count shows only for stacks.
func set_item(texture: Texture2D, count: int = 0) -> void:
	_icon.texture = texture
	_icon.visible = texture != null
	_count.text = str(count)
	_count.visible = count > 1
