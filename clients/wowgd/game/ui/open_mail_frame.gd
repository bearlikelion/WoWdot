@tool
class_name OpenMailFrame
extends Control

signal open_requested
signal close_requested
signal take_money_requested(mail_id: int)
signal take_item_requested(mail_id: int)
signal delete_requested(mail_id: int)

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
	open_requested.emit()


func mail_id() -> int:
	return _mail.get("id", 0)


func _on_money_pressed() -> void:
	take_money_requested.emit(mail_id())


func _on_package_pressed() -> void:
	take_item_requested.emit(mail_id())


func _on_delete_pressed() -> void:
	delete_requested.emit(mail_id())
	close_requested.emit()
