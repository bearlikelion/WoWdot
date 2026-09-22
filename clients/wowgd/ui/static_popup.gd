class_name StaticPopup
extends Control

const MIN_BUTTON_WIDTH: float = 120.0
const BUTTON_TEXT_PADDING: float = 20.0
const BUTTON_GAP: float = 13.0
# Button1's top right sits this far off the bottom centre of the text.
const BUTTON_OFFSET: Vector2 = Vector2(-6.0, 8.0)
const BORDER_PADDING: float = 16.0

# The format and seconds left of a popup that counts down, as the CAMP dialog does.
var _countdown_text: String = ""
var _time_left: float = 0.0

var _on_accept: Callable
var _on_cancel: Callable

@onready var _text: Label = %StaticPopup1Text
@onready var _accept: BaseButton = %StaticPopup1Button1
@onready var _cancel: BaseButton = %StaticPopup1Button2
@onready var _edit: LineEdit = %StaticPopup1EditBox


func _ready() -> void:
	for node: CanvasItem in [
		%StaticPopup1AlertIcon, %StaticPopup1CloseButton, %StaticPopup1EditBox,
		%StaticPopup1WideEditBox, %StaticPopup1MoneyFrame,
	]:
		node.hide()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_accept.pressed.connect(_on_accept_pressed)
	_cancel.pressed.connect(cancel)


func _process(delta: float) -> void:
	if _countdown_text.is_empty() or not visible:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_countdown_text = ""
		hide()
		return
	_text.text = _countdown_text % _seconds_text()


# StaticPopup_Show for a two button question, sized to its text as StaticPopup_Resize does.
func ask(
	text: String, on_accept: Callable, accept_key: String = "YES", cancel_key: String = "NO",
	on_cancel: Callable = Callable(),
) -> void:
	_edit.hide()
	_lay_out(text, on_accept, accept_key, cancel_key, on_cancel, 0.0)


# A timed popup with one button that calls it off, such as the twenty seconds before a logout.
func count_down(text: String, seconds: float, on_cancel: Callable) -> void:
	_edit.hide()
	_countdown_text = text
	_time_left = seconds
	_lay_out(text % _seconds_text(), on_cancel, "CANCEL", "CANCEL", on_cancel, 0.0)
	_cancel.hide()
	_accept.position.x = (size.x - _accept.size.x) / 2.0


func stop_count_down() -> void:
	if not _countdown_text.is_empty():
		_countdown_text = ""
		hide()


# The same popup with an edit box under the question, as naming a pet needs.
func ask_name(text: String, on_accept: Callable) -> void:
	_edit.text = ""
	_edit.show()
	_edit.grab_focus.call_deferred()
	_lay_out(
		text, func() -> void: on_accept.call(_edit.text), "OKAY", "CANCEL", Callable(),
		_edit.size.y + BUTTON_GAP,
	)


func _lay_out(
	text: String, on_accept: Callable, accept_key: String, cancel_key: String,
	on_cancel: Callable, extra_height: float,
) -> void:
	_on_accept = on_accept
	_on_cancel = on_cancel
	_cancel.show()
	_text.text = text
	_set_button(_accept, WowStrings.get_text(accept_key))
	_set_button(_cancel, WowStrings.get_text(cancel_key))
	var text_bottom: float = _text.position.y + _text.get_minimum_size().y
	if _edit.visible:
		_edit.position = Vector2((size.x - _edit.size.x) / 2.0, text_bottom + BUTTON_GAP)
	_accept.position = Vector2(
		size.x / 2.0 + BUTTON_OFFSET.x - _accept.size.x,
		text_bottom + BUTTON_OFFSET.y + extra_height,
	)
	_cancel.position = _accept.position + Vector2(_accept.size.x + BUTTON_GAP, 0.0)
	size.y = BORDER_PADDING + _text.get_minimum_size().y + BUTTON_OFFSET.y + extra_height \
	+ _accept.size.y + BORDER_PADDING
	show()


# StaticPopup_EscapePressed: false when there was nothing to close.
func cancel() -> bool:
	if not visible:
		return false
	hide()
	if _on_cancel.is_valid():
		_on_cancel.call()
	return true


func _seconds_text() -> Array:
	var left: int = ceili(_time_left)
	return [left, WowStrings.get_text("SECONDS" if left == 1 else "SECONDS_P1")]


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
