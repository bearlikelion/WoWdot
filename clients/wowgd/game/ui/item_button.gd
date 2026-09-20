@tool
class_name ItemButton
extends WowButton

signal right_clicked

## The wire bag and slot this button shows, or (-1, -1) when it holds no movable item.
var address: Vector2i = -Vector2i.ONE

## Asked how many to move when a stack is dropped with Shift held; unset, the whole stack moves.
static var split_prompt: Callable

@onready var _icon: TextureRect = %IconTexture
@onready var _count: Label = %Count


func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		right_clicked.emit()


# PickupContainerItem: dragging lifts the item, and dropping swaps it with what is there.
func _get_drag_data(_at_position: Vector2) -> Variant:
	if Engine.is_editor_hint() or address.x < 0 or Inventory.item_at(address) == 0:
		return null
	var preview: TextureRect = TextureRect.new()
	preview.texture = _icon.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = size
	set_drag_preview(preview)
	return {"item_address": address, "stack": Inventory.stack_count(Inventory.item_at(address))}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return address.x >= 0 and data is Dictionary and data.has("item_address")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data["stack"] > 1 and Input.is_key_pressed(KEY_SHIFT) and split_prompt.is_valid():
		split_prompt.call(data["item_address"], address, data["stack"])
		return
	Inventory.move(data["item_address"], address)


# SetItemButtonTexture and SetItemButtonCount: a count shows only for stacks.
func set_item(texture: Texture2D, count: int = 0) -> void:
	_icon.texture = texture
	_icon.visible = texture != null
	_count.text = str(count)
	_count.visible = count > 1
