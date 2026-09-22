class_name HelpFrame
extends Control

signal close_requested
signal ticket_requested(text: String, category: int)

enum Page { HOME, GM_TALK, REPORT_ISSUE, LAG, STUCK, OPEN_TICKET }

# 3.3.5 tickets carry no category, so the wire always gets the gameplay one.
const DEFAULT_CATEGORY: int = 1
# SMSG_GMTICKET_GETTICKET's status when a ticket is open.
const HAS_TICKET: int = 6
const TEXT_MARGIN: float = 45.0

var _category: int = DEFAULT_CATEGORY
var _has_ticket: bool = false

@onready var _pages: Dictionary[Page, Control] = {
	Page.HOME: %KnowledgeBaseFrame, Page.GM_TALK: %HelpFrameGMTalk,
	Page.REPORT_ISSUE: %HelpFrameReportIssue, Page.LAG: %HelpFrameLag,
	Page.STUCK: %HelpFrameStuck, Page.OPEN_TICKET: %HelpFrameOpenTicket,
}
@onready var _text: TextEdit = %HelpFrameOpenTicketEditBox


func _ready() -> void:
	%KnowledgeBaseFrameGMTalk.pressed.connect(_show_page.bind(Page.GM_TALK))
	%KnowledgeBaseFrameReportIssue.pressed.connect(_show_page.bind(Page.REPORT_ISSUE))
	%KnowledgeBaseFrameLag.pressed.connect(_show_page.bind(Page.LAG))
	%KnowledgeBaseFrameStuck.pressed.connect(_show_page.bind(Page.STUCK))
	%KnowledgeBaseFrameEditTicket.pressed.connect(_show_page.bind(Page.OPEN_TICKET))
	%KnowledgeBaseFrameAbandonTicket.pressed.connect(
		WowClient.session.send_packet.bind("CMSG_GMTICKET_DELETETICKET", PackedByteArray())
	)
	for button: BaseButton in [
		%HelpFrameGMTalkOpenTicket, %HelpFrameReportIssueOpenTicket, %HelpFrameStuckOpenTicket,
	]:
		button.pressed.connect(_show_page.bind(Page.OPEN_TICKET))
	for button: BaseButton in [
		%HelpFrameGMTalkCancel, %HelpFrameReportIssueCancel, %HelpFrameLagCancel,
		%HelpFrameStuckCancel, %HelpFrameOpenTicketCancel,
	]:
		button.pressed.connect(_show_page.bind(Page.HOME))
	%HelpFrameCloseButton.pressed.connect(close_requested.emit)
	%KnowledgeBaseFrameCancel.pressed.connect(close_requested.emit)
	%HelpFrameOpenTicketSubmit.pressed.connect(_on_submit_pressed)
	WowClient.session.packet_received.connect(_on_packet_received)
	visibility_changed.connect(_on_visibility_changed)
	for page: Page in [Page.GM_TALK, Page.REPORT_ISSUE, Page.STUCK]:
		_flow.call_deferred(_pages[page])
	hide()


func _show_page(page: Page) -> void:
	for other: Page in _pages:
		_pages[other].visible = other == page
	if page == Page.OPEN_TICKET:
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


# An open ticket swaps the home buttons for Edit and Abandon, as HelpFrame_OnEvent does.
func _show_ticket(text: String) -> void:
	_text.text = text
	(%HelpFrameOpenTicketSubmitText as Label).text = WowStrings.get_text(
		"EDIT_TICKET" if _has_ticket else "SUBMIT"
	)
	(%HelpFrameOpenTicketLabel as Label).text = WowStrings.get_text(
		"HELPFRAME_OPENTICKET_EDITTEXT" if _has_ticket else "HELPFRAME_OPENTICKET_TEXT"
	)
	%KnowledgeBaseFrameGMTalk.visible = not _has_ticket
	%KnowledgeBaseFrameReportIssue.visible = not _has_ticket
	%HelpFrameStuckOpenTicket.visible = not _has_ticket
	%KnowledgeBaseFrameEditTicket.visible = _has_ticket
	%KnowledgeBaseFrameAbandonTicket.visible = _has_ticket


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
