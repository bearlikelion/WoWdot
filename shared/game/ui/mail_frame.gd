@tool
class_name MailFrame
extends Control

signal open_requested
signal close_requested
signal mail_opened(mail: Dictionary)
signal message_added(text: String)

const MAILS_PER_PAGE: int = 7
const AUCTION_SENDER: String = "Auction House"
# Message types, which say how the sender field reads.
enum Sender { NORMAL = 0, CREATURE = 1, GAMEOBJECT = 2, AUCTION = 3, ITEM = 4 }
enum Tab { INBOX, SEND }
# SMSG_SEND_MAIL_RESULT actions, and MAIL_OK.
enum MailAction { SENT, MONEY_TAKEN, ITEM_TAKEN, RETURNED, DELETED, MADE_PERMANENT }

const MAIL_OK: int = 0
const COPPER_PER_SILVER: int = 100
const COPPER_PER_GOLD: int = 10000
const DEFAULT_STATIONERY: int = 41

var _guid: int = 0
var _mails: Array[Dictionary] = []
var _page: int = 0
var _tab: Tab = Tab.INBOX
# True while a list was asked for by opening a mailbox, rather than to follow an action.
var _opening: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for i: int in MAILS_PER_PAGE:
		var button: BaseButton = get_node("%%MailItem%dButton" % (i + 1))
		button.pressed.connect(_on_mail_pressed.bind(i))
	%InboxPrevPageButton.pressed.connect(_turn_page.bind(-1))
	%InboxNextPageButton.pressed.connect(_turn_page.bind(1))
	%InboxCloseButton.pressed.connect(close_requested.emit)
	%MailFrameTab1.pressed.connect(show_tab.bind(Tab.INBOX))
	%MailFrameTab2.pressed.connect(show_tab.bind(Tab.SEND))
	%SendMailCancelButton.pressed.connect(show_tab.bind(Tab.INBOX))
	%SendMailMailButton.pressed.connect(send)
	WowClient.session.packet_received.connect(_on_packet_received)
	hide()


# CMSG_GET_MAIL_LIST: a mailbox answers with everything waiting for the player.
func open(mailbox_guid: int) -> void:
	_guid = mailbox_guid
	_page = 0
	_opening = true
	_request_list()


func _request_list() -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, _guid)
	WowClient.session.send_packet("CMSG_GET_MAIL_LIST", payload)


func mailbox() -> int:
	return _guid


func show_tab(tab: Tab) -> void:
	_tab = tab
	%InboxFrame.visible = tab == Tab.INBOX
	%SendMailFrame.visible = tab == Tab.SEND
	refresh()


# CMSG_SEND_MAIL: the letter, with whatever money the three coin boxes hold.
func send() -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, _guid)
	payload.append_array(_text_bytes((%SendMailNameEditBox as LineEdit).text))
	payload.append_array(_text_bytes((%SendMailSubjectEditBox as LineEdit).text))
	payload.append_array(_text_bytes((%SendMailBodyEditBox as LineEdit).text))
	# Stationery, package, the attached item, money, cash on delivery, then the two the client pads with.
	var tail: PackedByteArray = []
	tail.resize(33)
	tail.encode_u32(0, DEFAULT_STATIONERY)
	tail.encode_u32(4, 0)
	tail.encode_u64(8, 0)
	tail.encode_u32(16, _money_typed())
	tail.encode_u32(20, 0)
	payload.append_array(tail)
	WowClient.session.send_packet("CMSG_SEND_MAIL", payload)


func take_money(mail_id: int) -> void:
	_send("CMSG_MAIL_TAKE_MONEY", mail_id)


func take_item(mail_id: int) -> void:
	_send("CMSG_MAIL_TAKE_ITEM", mail_id)


func delete(mail_id: int) -> void:
	_send("CMSG_MAIL_DELETE", mail_id)


func return_to_sender(mail_id: int) -> void:
	_send("CMSG_MAIL_RETURN_TO_SENDER", mail_id)


func refresh() -> void:
	if _tab == Tab.SEND:
		return
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


func _text_bytes(text: String) -> PackedByteArray:
	var bytes: PackedByteArray = text.to_utf8_buffer()
	bytes.append(0)
	return bytes


func _money_typed() -> int:
	var gold: int = (%SendMailMoneyGold as LineEdit).text.to_int()
	var silver: int = (%SendMailMoneySilver as LineEdit).text.to_int()
	var copper: int = (%SendMailMoneyCopper as LineEdit).text.to_int()
	return gold * COPPER_PER_GOLD + silver * COPPER_PER_SILVER + copper


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
	var reader: PacketReader = PacketReader.new(payload)
	if opcode == "SMSG_MAIL_LIST_RESULT":
		_mails = _read_mails(payload)
		refresh()
		if _opening:
			_opening = false
			open_requested.emit()
		return
	if opcode != "SMSG_SEND_MAIL_RESULT":
		return
	reader.u32()
	var action: MailAction = reader.u32() as MailAction
	var error: int = reader.u32()
	if action == MailAction.SENT and error == MAIL_OK:
		message_added.emit(WowStrings.get_text("ERR_MAIL_SENT", "Mail sent."))
		show_tab(Tab.INBOX)
	_request_list()


func _read_mails(payload: PackedByteArray) -> Array[Dictionary]:
	var reader: PacketReader = PacketReader.new(payload)
	var mails: Array[Dictionary] = []
	for i: int in reader.u8():
		var mail: Dictionary = {"id": reader.u32()}
		var type: Sender = reader.u8() as Sender
		mail["from_player"] = type == Sender.NORMAL
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
