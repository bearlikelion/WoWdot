@tool
class_name ItemTextFrame
extends Control

signal open_requested
signal close_requested

var _title: String = ""
var _pages: PackedInt32Array = []
var _page: int = 0
var _next: int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	%ItemTextCloseButton.pressed.connect(close_requested.emit)
	%ItemTextPrevPageButton.pressed.connect(_turn.bind(-1))
	%ItemTextNextPageButton.pressed.connect(_turn.bind(1))
	WowClient.session.packet_received.connect(_on_packet_received)
	# The converted label ignores the mouse, which would leave a long page out of the wheel's reach.
	(%ItemTextPageText as RichTextLabel).mouse_filter = Control.MOUSE_FILTER_PASS
	(%ItemTextPageText as RichTextLabel).scroll_following = false
	hide()


# A book or a plaque: its first page is asked for, and each page names the one after it.
func read(title: String, first_page: int) -> void:
	_title = title
	_pages = [first_page]
	_page = 0
	_ask(first_page)


# A letter's text comes whole, under the id its mail or item carries.
func read_letter(title: String, text_id: int, mail_id: int, item_guid: int = 0) -> void:
	_title = title
	_pages = []
	var payload: PackedByteArray = []
	if PacketReader.wotlk:
		payload.resize(8)
		payload.encode_u64(0, item_guid)
		WowClient.session.send_packet("CMSG_ITEM_TEXT_QUERY", payload)
		return
	payload.resize(12)
	payload.encode_u32(0, text_id)
	payload.encode_u32(4, mail_id)
	WowClient.session.send_packet("CMSG_ITEM_TEXT_QUERY", payload)


func _ask(page: int) -> void:
	var payload: PackedByteArray = []
	# 3.3.5 follows the page with the guid of the object it was read from.
	payload.resize(12 if PacketReader.wotlk else 4)
	payload.encode_u32(0, page)
	WowClient.session.send_packet("CMSG_PAGE_TEXT_QUERY", payload)


func _turn(by: int) -> void:
	if _page + by == _pages.size():
		_pages.append(_next)
	_page += by
	_ask(_pages[_page])


func _show_text(text: String) -> void:
	%ItemTextTitleText.text = _title
	(%ItemTextPageText as RichTextLabel).text = WowStrings.to_bbcode(text)
	(%ItemTextPageText as RichTextLabel).scroll_to_line(0)
	%ItemTextCurrentPage.visible = _pages.size() > 1 or _next != 0
	%ItemTextCurrentPage.text = WowStrings.format(WowStrings.get_text("PAGE_NUMBER"), [_page + 1])
	%ItemTextPrevPageButton.visible = _page > 0
	%ItemTextNextPageButton.visible = _next != 0
	open_requested.emit()


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	if opcode == "SMSG_PAGE_TEXT_QUERY_RESPONSE":
		if _pages.is_empty() or reader.u32() != _pages[_page]:
			return
		var text: String = reader.cstring()
		_next = reader.u32()
		_show_text(text)
	elif opcode == "SMSG_ITEM_TEXT_QUERY_RESPONSE":
		if PacketReader.wotlk:
			if reader.u8() != 0:
				return
			reader.u64()
		else:
			reader.u32()
		_next = 0
		_page = 0
		_show_text(reader.cstring())
