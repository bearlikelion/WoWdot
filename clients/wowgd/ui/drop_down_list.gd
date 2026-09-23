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


# Each entry takes "text" and "id", and optionally "title" for a heading that cannot be picked.
# UIDropDownMenu_SetWidth on a converted dropdown: the middle stretches, the rest follows it.
static func set_width(frame: Control, width: float) -> void:
	const CAP: float = 25.0
	# UIDropDownMenuTemplate pins the text and button this far in from the right cap's edge.
	const TEXT_INSET: float = 43.0
	const BUTTON_INSET: float = 16.0
	const BUTTON_SIZE: float = 24.0
	var middle: Control = frame.get_node(String(frame.name) + "Middle")
	middle.offset_right = middle.offset_left + width
	var right: Control = frame.get_node(String(frame.name) + "Right")
	right.offset_left = middle.offset_right
	right.offset_right = right.offset_left + CAP
	var text: Control = frame.get_node(String(frame.name) + "Text")
	text.offset_right = right.offset_right - TEXT_INSET
	text.offset_left = text.offset_right - (width - CAP)
	var button: Control = frame.get_node(String(frame.name) + "Button")
	button.offset_right = right.offset_right - BUTTON_INSET
	button.offset_left = button.offset_right - BUTTON_SIZE
	frame.offset_left = frame.offset_right - (width + CAP * 2.0)


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
		widest = maxf(widest, label.get_minimum_size().x + TEXT_PADDING)
	size = Vector2(widest + LEFT_INSET * 2.0, entries.size() * BUTTON_HEIGHT + BORDER_HEIGHT * 2.0)
	for i: int in entries.size():
		var button: Control = get_node("%%DropDownList1Button%d" % (i + 1))
		button.position = Vector2(LEFT_INSET, BORDER_HEIGHT + i * BUTTON_HEIGHT)
		button.size = Vector2(widest, BUTTON_HEIGHT)
		(get_node("%%DropDownList1Button%dNormalText" % (i + 1)) as Label).size.x = widest
	position = at.min(get_viewport_rect().size - size).max(Vector2.ZERO)
	show()


func _on_button_pressed(index: int) -> void:
	hide()
	if index < _ids.size() and _ids[index] >= 0:
		entry_selected.emit(_ids[index])
