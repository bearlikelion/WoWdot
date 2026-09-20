@tool
class_name MailFrame
extends Control

signal open_requested
signal close_requested
signal mail_opened(mail: Dictionary)

const MAILS_PER_PAGE: int = 7
const AUCTION_SENDER: String = "Auction House"
# Message types, which say how the sender field reads.
enum Sender { NORMAL = 0, CREATURE = 1, GAMEOBJECT = 2, AUCTION = 3, ITEM = 4 }

var _guid: int = 0
var _mails: Array[Dictionary] = []
var _page: int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for i: int in MAILS_PER_PAGE:
		var button: BaseButton = get_node("%%MailItem%dButton" % (i + 1))
		button.pressed.connect(_on_mail_pressed.bind(i))
	%InboxPrevPageButton.pressed.connect(_turn_page.bind(-1))
	%InboxNextPageButton.pressed.connect(_turn_page.bind(1))
	%InboxCloseButton.pressed.connect(close_requested.emit)
	WowClient.session.packet_received.connect(_on_packet_received)
	hide()


# CMSG_GET_MAIL_LIST: a mailbox answers with everything waiting for the player.
func open(mailbox_guid: int) -> void:
	_guid = mailbox_guid
	_page = 0
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, mailbox_guid)
	WowClient.session.send_packet("CMSG_GET_MAIL_LIST", payload)


func mailbox() -> int:
	return _guid


func take_money(mail_id: int) -> void:
	_send("CMSG_MAIL_TAKE_MONEY", mail_id)


func take_item(mail_id: int) -> void:
	_send("CMSG_MAIL_TAKE_ITEM", mail_id)


func delete(mail_id: int) -> void:
	_send("CMSG_MAIL_DELETE", mail_id)


func refresh() -> void:
	var pages: int = maxi(1, ceili(float(_mails.size()) / MAILS_PER_PAGE))
	_page = clampi(_page, 0, pages - 1)
	%InboxCurrentPage.text = "%d / %d" % [_page + 1, pages]
	%InboxPrevPageButton.disabled = _page == 0
	%InboxNextPageButton.disabled = _page + 1 >= pages
	for i: int in MAILS_PER_PAGE:
		var index: int = _page * MAILS_PER_PAGE + i
		var mail: Dictionary = _mails[index] if index < _mails.size() else {}
		(get_node("%%MailItem%d" % (i + 1)) as Control).visible = not mail.is_empty()
		if mail.is_empty():
			continue
		(get_node("%%MailItem%dSender" % (i + 1)) as Label).text = mail["sender"]
		(get_node("%%MailItem%dSubject" % (i + 1)) as Label).text = mail["subject"]
		(get_node("%%MailItem%dExpireTimeText" % (i + 1)) as Label).text = "%d d" % mail["days"]
		var icon: TextureRect = get_node("%%MailItem%dButtonIcon" % (i + 1))
		icon.texture = Inventory.icon(mail["item_entry"]) if mail["item_entry"] != 0 else null
		icon.visible = icon.texture != null


func _send(opcode: String, mail_id: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(12)
	payload.encode_u64(0, _guid)
	payload.encode_u32(8, mail_id)
	WowClient.session.send_packet(opcode, payload)


func _turn_page(by: int) -> void:
	_page += by
	refresh()


func _on_mail_pressed(index: int) -> void:
	var at: int = _page * MAILS_PER_PAGE + index
	if at >= _mails.size():
		return
	_send("CMSG_MAIL_MARK_AS_READ", _mails[at]["id"])
	mail_opened.emit(_mails[at])


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_MAIL_LIST_RESULT":
		return
	_mails = _read_mails(payload)
	refresh()
	open_requested.emit()


func _read_mails(payload: PackedByteArray) -> Array[Dictionary]:
	var reader: PacketReader = PacketReader.new(payload)
	var mails: Array[Dictionary] = []
	for i: int in reader.u8():
		var mail: Dictionary = {"id": reader.u32()}
		var type: Sender = reader.u8() as Sender
		mail["sender"] = _sender_name(type, reader)
		mail["subject"] = reader.cstring()
		mail["text_id"] = reader.u32()
		reader.u32()
		mail["stationery"] = reader.u32()
		mail["item_entry"] = reader.u32()
		for skipped: int in 3:
			reader.u32()
		mail["stack"] = reader.u8()
		for skipped: int in 3:
			reader.u32()
		mail["money"] = reader.u32()
		mail["cod"] = reader.u32()
		mail["read"] = reader.u32()
		mail["days"] = ceili(reader.f32())
		mails.append(mail)
	return mails


func _sender_name(type: Sender, reader: PacketReader) -> String:
	if type == Sender.NORMAL:
		return WowClient.session.get_object_name(reader.u64())
	if type == Sender.ITEM:
		return ""
	var entry: int = reader.u32()
	if type == Sender.AUCTION:
		return WowStrings.get_text("AUCTION_HOUSE", AUCTION_SENDER)
	return WowClient.session.get_creature_template(entry).get("name", "")
