class_name HelpFrame
extends Control

signal close_requested
signal ticket_requested(text: String, category: int)

enum Page { HOME, GM, OPEN_TICKET }

const CATEGORY_ROWS: int = 10
# The gameplay category, which a ticket filed without the window falls under.
const DEFAULT_CATEGORY: int = 1
# GMTicketCategory.dbc: the id the wire carries, then the name.
const CATEGORY_NAME_COLUMN: int = 1
# SMSG_GMTICKET_GETTICKET's status when a ticket is open.
const HAS_TICKET: int = 6
const TEXT_MARGIN: float = 45.0

var _page: Page = Page.HOME
var _offset: int = 0
var _category: int = DEFAULT_CATEGORY
var _has_ticket: bool = false
var _categories: WowDBC

@onready var _pages: Dictionary[Page, Control] = {
	Page.HOME: %HelpFrameHome, Page.GM: %HelpFrameGM, Page.OPEN_TICKET: %HelpFrameOpenTicket,
}
@onready var _text: TextEdit = %HelpFrameOpenTicketText
@onready var _scroll: WowScrollFrame = %HelpFrameGMScrollFrame


func _ready() -> void:
	_categories = WowDBC.open(WowAssets.archive, "GMTicketCategory")
	for i: int in CATEGORY_ROWS:
		_row(i).pressed.connect(_on_category_pressed.bind(i))
	_scroll.faux = true
	_scroll.scrolled.connect(_on_scrolled)
	%HelpFrameHomeIssues.pressed.connect(_show_page.bind(Page.GM))
	%HelpFrameGMBack.pressed.connect(_show_page.bind(Page.HOME))
	for button: BaseButton in [
		%HelpFrameCloseButton, %HelpFrameHomeCancel, %HelpFrameGMCancel, %HelpFrameOpenTicketCancel,
	]:
		button.pressed.connect(close_requested.emit)
	%HelpFrameOpenTicketSubmit.pressed.connect(_on_submit_pressed)
	WowClient.session.packet_received.connect(_on_packet_received)
	visibility_changed.connect(_on_visibility_changed)
	_flow.call_deferred(%HelpFrameHome)
	hide()


func _show_page(page: Page) -> void:
	_page = page
	for other: Page in _pages:
		_pages[other].visible = other == page
	if page == Page.GM:
		_list_categories()
	elif page == Page.OPEN_TICKET:
		_text.grab_focus()


# Stock anchors each paragraph under the last; the converted scene fixes them one line tall.
func _flow(page: Control) -> void:
	var tops: Dictionary[Control, float] = {}
	var heights: Dictionary[Control, float] = {}
	for child: Control in page.get_children():
		tops[child] = child.position.y
		heights[child] = child.size.y
		var label: Label = child as Label
		if label:
			label.text = WowStrings.strip_colors(label.text)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.size.x = page.size.x - label.position.x - TEXT_MARGIN
	# A label only reports its wrapped height once it has been laid out at the new width.
	await get_tree().process_frame
	var pushed: float = 0.0
	for child: Control in page.get_children():
		# Whatever hangs off the bottom edge, like Cancel, stays where it is.
		if child.anchor_top > 0.0:
			continue
		child.position.y = tops[child] + pushed
		if child is Label:
			child.size.y = maxf(child.get_minimum_size().y, heights[child])
			pushed += child.size.y - heights[child]


func _list_categories() -> void:
	_scroll.set_range(maxi(_categories.row_count() - CATEGORY_ROWS, 0))
	for i: int in CATEGORY_ROWS:
		var index: int = i + _offset
		_row(i).visible = index < _categories.row_count()
		if _row(i).visible:
			var label: Label = get_node("%%HelpFrameButton%dText" % (i + 1))
			label.text = _categories.get_string(index, CATEGORY_NAME_COLUMN)


func _row(i: int) -> BaseButton:
	return get_node("%%HelpFrameButton%d" % (i + 1))


# An open ticket turns Submit into Edit Ticket, as HelpFrameOpenTicket_OnEvent does.
func _show_ticket(text: String) -> void:
	_text.text = text
	(%HelpFrameOpenTicketSubmitText as Label).text = WowStrings.get_text(
		"EDIT_TICKET" if _has_ticket else "SUBMIT"
	)
	(%HelpFrameOpenTicketLabel as Label).text = WowStrings.get_text(
		"HELPFRAME_OPENTICKET_EDITTEXT" if _has_ticket else "HELPFRAME_OPENTICKET_TEXT"
	)


func _on_category_pressed(i: int) -> void:
	_category = _categories.get_uint(i + _offset, 0)
	_show_page(Page.OPEN_TICKET)


func _on_scrolled(value: float) -> void:
	if roundi(value) != _offset:
		_offset = roundi(value)
		_list_categories()


func _on_submit_pressed() -> void:
	if _has_ticket:
		var payload: PackedByteArray = [_category]
		payload.append_array(_text.text.to_utf8_buffer())
		payload.append(0)
		WowClient.session.send_packet("CMSG_GMTICKET_UPDATETEXT", payload)
	else:
		ticket_requested.emit(_text.text, _category)
	close_requested.emit()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_show_page(Page.HOME)
		WowClient.session.send_packet("CMSG_GMTICKET_GETTICKET", PackedByteArray())


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode == "SMSG_GMTICKET_DELETETICKET":
		_has_ticket = false
		_show_ticket("")
	elif opcode == "SMSG_GMTICKET_GETTICKET":
		var reader: PacketReader = PacketReader.new(payload)
		_has_ticket = reader.u32() == HAS_TICKET
		if _has_ticket and PacketReader.wotlk:
			reader.u32()
		var text: String = reader.cstring() if _has_ticket else ""
		if _has_ticket and not PacketReader.wotlk:
			_category = reader.u8()
		_show_ticket(text)
