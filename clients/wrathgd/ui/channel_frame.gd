class_name ChannelFrame
extends Control

const CHANNEL_BUTTONS: int = 20
const MEMBER_BUTTONS: int = 22
# ChannelMemberFlags.
const OWNER: int = 0x01
const MODERATOR: int = 0x02
const LEADER_ICON: String = "Interface\\GroupFrame\\UI-Group-LeaderIcon.blp"
const ASSISTANT_ICON: String = "Interface\\GroupFrame\\UI-Group-AssistantIcon.blp"

var _selected: String = ""
# The selected channel's members as {guid, flags}, in the order the server listed them.
var _members: Array[Dictionary] = []


func _ready() -> void:
	for i: int in CHANNEL_BUTTONS:
		(get_node("%%ChannelButton%d" % (i + 1)) as BaseButton).pressed.connect(_select.bind(i))
	# Voice chat and the channel drop downs are not ported.
	for unported: CanvasItem in [
		%ChannelFrameAutoJoin, %ChannelListDropDown, %ChannelRosterDropDown,
	]:
		unported.hide()
	%ChannelFrameDaughterFrame.hide()
	%ChannelFrameNewButton.pressed.connect(_toggle_new)
	%ChannelFrameDaughterFrameOkayButton.pressed.connect(_join)
	%ChannelFrameDaughterFrameCancelButton.pressed.connect(%ChannelFrameDaughterFrame.hide)
	%ChannelFrameDaughterFrameDetailCloseButton.pressed.connect(%ChannelFrameDaughterFrame.hide)
	var session: WowSession = WowClient.session
	session.packet_received.connect(_on_packet_received)
	session.name_received.connect(func(_guid: int, _name: String) -> void: _show_roster())
	visibility_changed.connect(_on_visibility_changed)


# ChannelList_Update, flat: each joined channel by its number.
func refresh() -> void:
	if not is_visible_in_tree():
		return
	var names: PackedStringArray = _channels()
	for i: int in CHANNEL_BUTTONS:
		var button: BaseButton = get_node("%%ChannelButton%d" % (i + 1))
		button.visible = i < names.size()
		if not button.visible:
			continue
		var text: Label = get_node("%%ChannelButton%dText" % (i + 1))
		text.text = "%d. %s" % [Channels.number_of(names[i]), names[i]]
		(get_node("%%ChannelButton%dCollapsed" % (i + 1)) as CanvasItem).hide()
		(get_node("%%ChannelButton%dSpeakerFrame" % (i + 1)) as CanvasItem).hide()
		(button as WowButton).checked = names[i] == _selected
	_show_roster()


static func _channels() -> PackedStringArray:
	var names: PackedStringArray = []
	for channel_name: String in Channels.joined:
		if not channel_name.is_empty():
			names.append(channel_name)
	return names


# ChannelList_OnClick: the roster comes from the display list, then the watch keeps it current.
func _select(index: int) -> void:
	var names: PackedStringArray = _channels()
	if index >= names.size():
		return
	_selected = names[index]
	_members.clear()
	Channels.request_display(_selected)
	WowClient.session.send_packet("CMSG_SET_CHANNEL_WATCH", _cstring(_selected))
	refresh()


# ChannelRoster_Update.
func _show_roster() -> void:
	if not is_visible_in_tree():
		return
	(%ChannelRosterChannelName as Label).text = _selected
	(%ChannelRosterChannelCount as Label).text = ""
	for i: int in MEMBER_BUTTONS:
		var button: Control = get_node("%%ChannelMemberButton%d" % (i + 1))
		button.visible = i < _members.size()
		if not button.visible:
			continue
		var member: Dictionary = _members[i]
		(button.get_node("Frame/Name") as Label).text = \
				WowClient.session.get_object_name(member["guid"])
		var flags: int = member["flags"]
		var rank: CanvasItem = get_node("%%ChannelMemberButton%dRank" % (i + 1))
		rank.visible = flags & (OWNER | MODERATOR) != 0
		if rank.visible:
			(get_node("%%ChannelMemberButton%dRankTexture" % (i + 1)) as TextureRect).texture = \
					PVPParentFrame.load_texture(LEADER_ICON if flags & OWNER else ASSISTANT_ICON)
		(get_node("%%ChannelMemberButton%dSpeakerFrame" % (i + 1)) as CanvasItem).hide()


func _toggle_new() -> void:
	var daughter: Control = %ChannelFrameDaughterFrame
	daughter.visible = not daughter.visible
	if not daughter.visible:
		return
	(%ChannelFrameDaughterFrameName as Label).text = WowStrings.get_text("CHANNEL_NEW_CHANNEL")
	(%ChannelFrameDaughterFrameChannelNameLabel as Label).text = \
			WowStrings.get_text("CHANNEL_CHANNEL_NAME")
	(%ChannelFrameDaughterFrameChannelPasswordLabel as Label).text = WowStrings.get_text("PASSWORD")
	(%ChannelFrameDaughterFrameChannelName as LineEdit).text = ""
	(%ChannelFrameDaughterFrameChannelPassword as LineEdit).text = ""
	(%ChannelFrameDaughterFrameChannelName as LineEdit).grab_focus.call_deferred()


func _join() -> void:
	var name_box: LineEdit = %ChannelFrameDaughterFrameChannelName
	var channel_name: String = name_box.text.strip_edges()
	if not channel_name.is_empty():
		Channels.join(channel_name, (%ChannelFrameDaughterFrameChannelPassword as LineEdit).text)
	%ChannelFrameDaughterFrame.hide()


static func _cstring(text: String) -> PackedByteArray:
	var payload: PackedByteArray = text.to_utf8_buffer()
	payload.append(0)
	return payload


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	match opcode:
		"SMSG_CHANNEL_NOTIFY":
			refresh()
		"SMSG_CHANNEL_LIST":
			var list: Dictionary = Channels.members(payload)
			if list["channel"] != _selected:
				return
			_members.clear()
			for i: int in list["guids"].size():
				_members.append({"guid": list["guids"][i], "flags": list["flags"][i]})
			_show_roster()
		"SMSG_USERLIST_ADD", "SMSG_USERLIST_UPDATE", "SMSG_USERLIST_REMOVE":
			_on_user_list(opcode, PacketReader.new(payload))


# Channel::JoinNotify, LeaveNotify and FlagsNotify for the watched channel.
func _on_user_list(opcode: String, reader: PacketReader) -> void:
	var guid: int = reader.u64()
	var flags: int = reader.u8() if opcode != "SMSG_USERLIST_REMOVE" else 0
	reader.u8()
	reader.u32()
	if reader.cstring() != _selected:
		return
	var at: int = _members.find_custom(
		func(member: Dictionary) -> bool: return member["guid"] == guid
	)
	if opcode == "SMSG_USERLIST_REMOVE":
		if at >= 0:
			_members.remove_at(at)
	elif at >= 0:
		_members[at]["flags"] = flags
	else:
		_members.append({"guid": guid, "flags": flags})
	_show_roster()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		if not _selected.is_empty():
			WowClient.session.send_packet("CMSG_CLEAR_CHANNEL_WATCH", _cstring(_selected))
		return
	if _selected.is_empty() and not _channels().is_empty():
		_select(0)
	else:
		refresh()
