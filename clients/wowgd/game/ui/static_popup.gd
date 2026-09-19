class_name StaticPopup
extends Control

const MIN_BUTTON_WIDTH: float = 120.0
const BUTTON_TEXT_PADDING: float = 20.0
const BUTTON_GAP: float = 13.0
# Button1's top right sits this far off the bottom centre of the text.
const BUTTON_OFFSET: Vector2 = Vector2(-6.0, 8.0)
const BORDER_PADDING: float = 16.0

var _on_accept: Callable

@onready var _text: Label = %StaticPopup1Text
@onready var _accept: BaseButton = %StaticPopup1Button1
@onready var _cancel: BaseButton = %StaticPopup1Button2


func _ready() -> void:
	for node: CanvasItem in [
		%StaticPopup1AlertIcon, %StaticPopup1CloseButton, %StaticPopup1EditBox,
		%StaticPopup1WideEditBox, %StaticPopup1MoneyFrame,
	]:
		node.hide()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_accept.pressed.connect(_on_accept_pressed)
	_cancel.pressed.connect(cancel)


# StaticPopup_Show for a yes or no question, sized to its text as StaticPopup_Resize does.
func ask(text: String, on_accept: Callable) -> void:
	_on_accept = on_accept
	_text.text = text
	_set_button(_accept, WowStrings.get_text("YES"))
	_set_button(_cancel, WowStrings.get_text("NO"))
	var text_bottom: float = _text.position.y + _text.get_minimum_size().y
	_accept.position = Vector2(
		size.x / 2.0 + BUTTON_OFFSET.x - _accept.size.x, text_bottom + BUTTON_OFFSET.y,
	)
	_cancel.position = _accept.position + Vector2(_accept.size.x + BUTTON_GAP, 0.0)
	size.y = BORDER_PADDING + _text.get_minimum_size().y + BUTTON_OFFSET.y + _accept.size.y \
	+ BORDER_PADDING
	show()


# StaticPopup_EscapePressed: false when there was nothing to close.
func cancel() -> bool:
	if not visible:
		return false
	hide()
	return true


func _set_button(button: BaseButton, text: String) -> void:
	var label: Label = get_node("%" + button.name + "Text")
	label.text = text
	var text_width: float = label.get_minimum_size().x
	var width: float = MIN_BUTTON_WIDTH
	if text_width > MIN_BUTTON_WIDTH:
		width = text_width + BUTTON_TEXT_PADDING
	button.size.x = width
	for child: Node in button.get_children():
		(child as Control).size.x = width


func _on_accept_pressed() -> void:
	hide()
	_on_accept.call()
