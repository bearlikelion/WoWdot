@tool
class_name OpenMailFrame
extends Control

signal open_requested
signal close_requested
signal take_money_requested(mail_id: int)
signal take_item_requested(mail_id: int)
signal delete_requested(mail_id: int)
signal return_requested(mail_id: int)

var _mail: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	%OpenMailCloseButton.pressed.connect(close_requested.emit)
	%OpenMailCancelButton.pressed.connect(close_requested.emit)
	%OpenMailDeleteButton.pressed.connect(_on_delete_pressed)
	%OpenMailMoneyButton.pressed.connect(_on_money_pressed)
	%OpenMailPackageButton.pressed.connect(_on_package_pressed)
	%OpenMailReplyButton.disabled = true
	%OpenMailInvoiceFrame.hide()
	hide()


# OpenMail_Update: the letter's sender, subject, body and whatever came with it.
func show_mail(mail: Dictionary) -> void:
	_mail = mail
	%OpenMailSender.text = mail["sender"]
	%OpenMailSubject.text = mail["subject"]
	(%OpenMailBodyText as Label).text = mail.get("body", "")
	%OpenMailMoneyButton.visible = mail["money"] > 0
	%OpenMailPackageButton.visible = mail["item_entry"] != 0
	%OpenMailLetterButton.visible = mail["text_id"] != 0
	var label: Label = %OpenMailDeleteButton.find_child("*Text", true, false)
	if label:
		label.text = WowStrings.get_text("MAIL_RETURN" if _returns() else "DELETE")
	open_requested.emit()


func mail_id() -> int:
	return _mail.get("id", 0)


func _on_money_pressed() -> void:
	take_money_requested.emit(mail_id())


func _on_package_pressed() -> void:
	take_item_requested.emit(mail_id())


# OpenMail_Update: a player's letter still holding something goes back rather than in the bin.
func _returns() -> bool:
	var holds: bool = _mail.get("money", 0) > 0 or _mail.get("item_entry", 0) != 0
	return holds and _mail.get("from_player", false)


func _on_delete_pressed() -> void:
	if _returns():
		return_requested.emit(mail_id())
	else:
		delete_requested.emit(mail_id())
	close_requested.emit()
