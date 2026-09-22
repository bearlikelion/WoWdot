class_name WhoFrame
extends Control

signal friend_requested(player_name: String)

const ROWS: int = 17
# WhoFrameColumn_SetWidth gives the four headers these widths, each butting against the last.
const COLUMN_WIDTHS: PackedFloat32Array = [83.0, 105.0, 32.0, 92.0]
const COLUMN_OVERLAP: float = 2.0
const HEADER_CAPS: float = 9.0
# What the second column shows, in the order WhoFrameDropDown lists them.
const COLUMNS: PackedStringArray = ["zone", "guild", "race"]

var _rows: Array[Dictionary] = []
var _column: int = 0
var _total: int = 0
var _selected: int = -1
var _offset: int = 0

@onready var _scroll: WowScrollFrame = %WhoListScrollFrame
@onready var _words: LineEdit = %WhoFrameEditBox


func _ready() -> void:
	for i: int in ROWS:
		_row(i).pressed.connect(_on_row_pressed.bind(i))
	%WhoFrameDropDown.hide()
	%WhoFrameColumnHeader2.pressed.connect(_cycle_column)
	_size_columns()
	_scroll.faux = true
	_scroll.scrolled.connect(_on_scrolled)
	_words.text_submitted.connect(func(_text: String) -> void: _ask())
	%WhoFrameWhoButton.pressed.connect(_ask)
	%WhoFrameAddFriendButton.pressed.connect(_on_add_friend_pressed)
	%WhoFrameGroupInviteButton.pressed.connect(_on_invite_pressed)
	WowClient.session.packet_received.connect(_on_packet_received)
	visibility_changed.connect(refresh)


func refresh() -> void:
	if not is_visible_in_tree():
		return
	var total_key: String = "WHO_FRAME_TOTAL_TEMPLATE"
	if _total != 1:
		total_key += "_P1"
	%WhoFrameTotals.text = WowStrings.format(WowStrings.get_text(total_key), [_total])
	_scroll.set_range(maxi(_rows.size() - ROWS, 0))
	for i: int in ROWS:
		var row: WowButton = _row(i)
		var index: int = i + _offset
		row.visible = index < _rows.size()
		if not row.visible:
			continue
		var found: Dictionary = _rows[index]
		(get_node("%%WhoFrameButton%dName" % (i + 1)) as Label).text = found["name"]
		(get_node("%%WhoFrameButton%dVariable" % (i + 1)) as Label).text = found[COLUMNS[_column]]
		(get_node("%%WhoFrameButton%dLevel" % (i + 1)) as Label).text = str(found["level"])
		(get_node("%%WhoFrameButton%dClass" % (i + 1)) as Label).text = found["class"]
		row.highlight_locked = index == _selected
	var picked: bool = _selected >= 0 and _selected < _rows.size()
	(%WhoFrameAddFriendButton as BaseButton).disabled = not picked
	(%WhoFrameGroupInviteButton as BaseButton).disabled = not picked


func _size_columns() -> void:
	var left: float = (%WhoFrameColumnHeader1 as Control).position.x
	for i: int in COLUMN_WIDTHS.size():
		var header: Control = get_node("%%WhoFrameColumnHeader%d" % (i + 1))
		header.position.x = left
		header.size.x = COLUMN_WIDTHS[i]
		var middle: Control = get_node("%%WhoFrameColumnHeader%dMiddle" % (i + 1))
		middle.size.x = COLUMN_WIDTHS[i] - HEADER_CAPS
		var right: Control = get_node("%%WhoFrameColumnHeader%dRight" % (i + 1))
		right.position.x = middle.position.x + middle.size.x
		var text: Label = get_node_or_null("%%WhoFrameColumnHeader%dText" % (i + 1))
		if text:
			text.size.x = COLUMN_WIDTHS[i] - HEADER_CAPS
		left += COLUMN_WIDTHS[i] - COLUMN_OVERLAP


func _ask() -> void:
	_words.release_focus()
	ServerNotices.ask_who(_words.text.split(" ", false))


func _row(index: int) -> WowButton:
	return get_node("%%WhoFrameButton%d" % (index + 1))


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_WHO":
		return
	var answer: Dictionary = ServerNotices.who_rows(payload)
	_rows = answer["rows"]
	_total = answer["total"]
	_selected = -1
	_offset = 0
	refresh()


# The stock drop down picks the column; here the header steps through the same choices.
func _cycle_column() -> void:
	_column = (_column + 1) % COLUMNS.size()
	var header: Label = get_node_or_null("%WhoFrameColumnHeader2Text")
	if header:
		header.text = WowStrings.get_text(COLUMNS[_column].to_upper())
	refresh()


func _on_row_pressed(index: int) -> void:
	_selected = index + _offset
	refresh()


func _on_scrolled(value: float) -> void:
	var offset: int = roundi(value)
	if offset != _offset:
		_offset = offset
		refresh()


func _on_add_friend_pressed() -> void:
	friend_requested.emit(_rows[_selected]["name"])


func _on_invite_pressed() -> void:
	PartyFrame.invite(_rows[_selected]["name"])
