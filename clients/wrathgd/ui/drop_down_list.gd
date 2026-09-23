@tool
class_name DropDownList
extends TextureButton

signal entry_selected(id: int)

const MAX_BUTTONS: int = 32
const BUTTON_HEIGHT: float = 16.0
const BORDER_HEIGHT: float = 15.0
# UIDropDownMenu_AddButton: the text plus room for the border, less the unused check box.
const TEXT_PADDING: float = 30.0
const LEFT_INSET: float = 15.0
const TITLE_COLOR: Color = Color(1.0, 0.82, 0.0)
# A checkable button's text starts past its check box.
const CHECK_INSET: float = 20.0
const TEXT_LEFT: float = -5.0

var _ids: PackedInt32Array = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for i: int in MAX_BUTTONS:
		var button: BaseButton = get_node("%%DropDownList1Button%d" % (i + 1))
		button.pressed.connect(_on_button_pressed.bind(i))
		get_node("%%DropDownList1Button%dCheck" % (i + 1)).hide()
	%DropDownList1MenuBackdrop.hide()
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		hide()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		hide()


# Entries take "text" and "id", plus "title" for an unpickable heading or "checked" for a check box.
func open(entries: Array[Dictionary], at: Vector2) -> void:
	_ids.clear()
	var widest: float = 0.0
	for i: int in MAX_BUTTONS:
		var button: Control = get_node("%%DropDownList1Button%d" % (i + 1))
		button.visible = i < entries.size()
		if not button.visible:
			continue
		var entry: Dictionary = entries[i]
		var is_title: bool = entry.get("title", false)
		var label: Label = get_node("%%DropDownList1Button%dNormalText" % (i + 1))
		label.text = entry["text"]
		label.modulate = TITLE_COLOR if is_title else Color.WHITE
		(button as BaseButton).disabled = is_title
		_ids.append(entry["id"] if entry.has("id") else -1)
		var inset: float = CHECK_INSET if entry.has("checked") else 0.0
		label.horizontal_alignment = \
				HORIZONTAL_ALIGNMENT_LEFT if inset else HORIZONTAL_ALIGNMENT_CENTER
		(get_node("%%DropDownList1Button%dCheck" % (i + 1)) as CanvasItem).visible = \
				entry.get("checked", false)
		widest = maxf(widest, label.get_minimum_size().x + TEXT_PADDING + inset)
	size = Vector2(widest + LEFT_INSET * 2.0, entries.size() * BUTTON_HEIGHT + BORDER_HEIGHT * 2.0)
	for i: int in entries.size():
		var button: Control = get_node("%%DropDownList1Button%d" % (i + 1))
		button.position = Vector2(LEFT_INSET, BORDER_HEIGHT + i * BUTTON_HEIGHT)
		button.size = Vector2(widest, BUTTON_HEIGHT)
		var label: Label = get_node("%%DropDownList1Button%dNormalText" % (i + 1))
		var inset: float = CHECK_INSET if entries[i].has("checked") else 0.0
		label.position.x = TEXT_LEFT + inset
		label.size.x = widest - inset
	position = at.min(get_viewport_rect().size - size).max(Vector2.ZERO)
	show()


func _on_button_pressed(index: int) -> void:
	hide()
	if index < _ids.size() and _ids[index] >= 0:
		entry_selected.emit(_ids[index])
