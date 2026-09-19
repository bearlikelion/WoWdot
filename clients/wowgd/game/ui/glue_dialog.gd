class_name GlueDialog
extends Control

signal status_cancelled
signal message_closed

# STATUS is the engine's "CANCEL" dialog, MESSAGE its "OKAY" one.
enum Kind { STATUS, MESSAGE }

# GlueDialog_Show: padding above the text, between text and button, and below the button.
const PAD_TOP: float = 16.0
const PAD_GAP: float = 8.0
const PAD_BOTTOM: float = 16.0

var kind: Kind = Kind.STATUS

@onready var _background: Control = %GlueDialogBackground
@onready var _text: Label = %GlueDialogText
@onready var _button: BaseButton = %GlueDialogButton1


func _ready() -> void:
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%GlueDialogButton2.hide()
	%GlueDialogEditBox.hide()
	_button.pressed.connect(_on_button_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_button_pressed()


func open(dialog_kind: Kind, text: String) -> void:
	kind = dialog_kind
	_text.text = text
	%GlueDialogButton1Text.text = WowStrings.get_text("CANCEL" if kind == Kind.STATUS else "OKAY")
	get_viewport().gui_release_focus()
	show()
	_fit()


func _fit() -> void:
	var text_height: float = _text.get_minimum_size().y
	_text.size.y = text_height
	var height: float = PAD_TOP + text_height + PAD_GAP + _button.size.y + PAD_BOTTOM
	_background.offset_top = -height / 2.0
	_background.offset_bottom = height / 2.0
	_button.position = Vector2(
		(_background.size.x - _button.size.x) / 2.0, height - PAD_BOTTOM - _button.size.y
	)


func _on_button_pressed() -> void:
	hide()
	if kind == Kind.STATUS:
		status_cancelled.emit()
	else:
		message_closed.emit()
