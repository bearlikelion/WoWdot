@tool
class_name FriendsFrame
extends Control

signal close_requested
signal name_requested(tab: Tab)
signal message_added(text: String)
signal guild_invited(inviter: String, guild_name: String)

enum Tab { FRIENDS, IGNORE, GUILD, RAID, WHO }
enum EventLogType { INVITE = 1, JOIN, PROMOTE, DEMOTE, REMOVE, QUIT }
# SMSG_GUILD_EVENT, as GuildEvents numbers them.
enum GuildEvent { PROMOTION, DEMOTION, MOTD, JOINED, LEFT, REMOVED, LEADER_IS, LEADER_CHANGED,
	DISBANDED, TABARD_CHANGED, RANK_RENAMED, ROSTER_UPDATE, SIGNED_ON, SIGNED_OFF }
# SMSG_GUILD_COMMAND_RESULT, as Guild's CommandErrors numbers them.
enum GuildResult { OK, INTERNAL, ALREADY_IN_GUILD, ALREADY_IN_GUILD_S, INVITED, ALREADY_INVITED_S,
	NAME_INVALID, NAME_EXISTS_S, PERMISSIONS, NOT_IN_GUILD, NOT_IN_GUILD_S, PLAYER_NOT_FOUND_S,
	NOT_ALLIED, RANK_TOO_HIGH_S, RANK_TOO_LOW_S }

const CONTACT_FRIEND: int = 0x01
const TAB_OVERLAP: float = -14.0
const CONTACT_IGNORED: int = 0x02
# Flags, a gold limit and six bank tabs of two words each.
const WOTLK_RANK_WORDS: int = 14
const ROWS: int = 10
const IGNORE_ROWS: int = 19
const GUILD_ROWS: int = 13
# SMSG_GUILD_QUERY_RESPONSE always carries ten rank names, whatever the guild uses.
const GUILD_RANKS: int = 10
const EVENT_LOG_TEXT: Dictionary[EventLogType, String] = {
	EventLogType.INVITE: "GUILDEVENT_TYPE_INVITE", EventLogType.JOIN: "GUILDEVENT_TYPE_JOIN",
	EventLogType.PROMOTE: "GUILDEVENT_TYPE_PROMOTE", EventLogType.DEMOTE: "GUILDEVENT_TYPE_DEMOTE",
	EventLogType.REMOVE: "GUILDEVENT_TYPE_REMOVE", EventLogType.QUIT: "GUILDEVENT_TYPE_QUIT",
}
# SMSG_FRIEND_STATUS results, as SocialMgr's FriendsResult numbers them.
enum Result { DB_ERROR, LIST_FULL, ONLINE, OFFLINE, NOT_FOUND, REMOVED, ADDED_ONLINE,
	ADDED_OFFLINE, ALREADY, SELF, ENEMY, IGNORE_FULL, IGNORE_SELF, IGNORE_NOT_FOUND,
	IGNORE_ALREADY, IGNORE_ADDED, IGNORE_REMOVED }

const STATUS_MESSAGES: Dictionary[Result, String] = {
	Result.LIST_FULL: "ERR_FRIEND_LIST_FULL", Result.ONLINE: "ERR_FRIEND_ONLINE_SS",
	Result.OFFLINE: "ERR_FRIEND_OFFLINE_S", Result.NOT_FOUND: "ERR_FRIEND_NOT_FOUND",
	Result.REMOVED: "ERR_FRIEND_REMOVED_S", Result.ADDED_ONLINE: "ERR_FRIEND_ADDED_S",
	Result.ADDED_OFFLINE: "ERR_FRIEND_ADDED_S", Result.ALREADY: "ERR_FRIEND_ALREADY_S",
	Result.SELF: "ERR_FRIEND_SELF", Result.ENEMY: "ERR_FRIEND_ENEMY",
	Result.IGNORE_FULL: "ERR_IGNORE_FULL", Result.IGNORE_SELF: "ERR_IGNORE_SELF",
	Result.IGNORE_NOT_FOUND: "ERR_IGNORE_NOT_FOUND",
	Result.IGNORE_ALREADY: "ERR_IGNORE_ALREADY_S", Result.IGNORE_ADDED: "ERR_IGNORE_ADDED_S",
	Result.IGNORE_REMOVED: "ERR_IGNORE_REMOVED_S",
}

const GUILD_MESSAGES: Dictionary[GuildEvent, String] = {
	GuildEvent.PROMOTION: "ERR_GUILD_PROMOTE_SSS", GuildEvent.DEMOTION: "ERR_GUILD_DEMOTE_SSS",
	GuildEvent.MOTD: "GUILD_MOTD_TEMPLATE", GuildEvent.JOINED: "ERR_GUILD_JOIN_S",
	GuildEvent.LEFT: "ERR_GUILD_LEAVE_S", GuildEvent.REMOVED: "ERR_GUILD_REMOVE_SS",
	GuildEvent.LEADER_CHANGED: "ERR_GUILD_LEADER_S", GuildEvent.DISBANDED: "ERR_GUILD_DISBANDED",
	GuildEvent.SIGNED_ON: "ERR_FRIEND_ONLINE_SS", GuildEvent.SIGNED_OFF: "ERR_FRIEND_OFFLINE_S",
}

const GUILD_ERRORS: Dictionary[GuildResult, String] = {
	GuildResult.INTERNAL: "ERR_GUILD_INTERNAL",
	GuildResult.ALREADY_IN_GUILD: "ERR_ALREADY_IN_GUILD",
	GuildResult.ALREADY_IN_GUILD_S: "ERR_ALREADY_IN_GUILD_S",
	GuildResult.INVITED: "ERR_INVITED_TO_GUILD",
	GuildResult.ALREADY_INVITED_S: "ERR_ALREADY_INVITED_TO_GUILD_S",
	GuildResult.NAME_INVALID: "ERR_GUILD_NAME_INVALID",
	GuildResult.NAME_EXISTS_S: "ERR_GUILD_NAME_EXISTS_S",
	GuildResult.PERMISSIONS: "ERR_GUILD_PERMISSIONS",
	GuildResult.NOT_IN_GUILD: "ERR_GUILD_PLAYER_NOT_IN_GUILD",
	GuildResult.NOT_IN_GUILD_S: "ERR_GUILD_PLAYER_NOT_IN_GUILD_S",
	GuildResult.PLAYER_NOT_FOUND_S: "ERR_GUILD_PLAYER_NOT_FOUND_S",
	GuildResult.NOT_ALLIED: "ERR_GUILD_NOT_ALLIED",
	GuildResult.RANK_TOO_HIGH_S: "ERR_GUILD_RANK_TOO_HIGH_S",
	GuildResult.RANK_TOO_LOW_S: "ERR_GUILD_RANK_TOO_LOW_S",
}

var _tab: Tab = Tab.FRIENDS
var _friends: Array[Dictionary] = []
var _ignored: Array[int] = []
var _selected: int = -1
var _awaiting_name: Dictionary[int, String] = {}
var _members: Array[Dictionary] = []
var _guild_name: String = ""
var _emblem: PackedInt32Array = []
var _rank_names: PackedStringArray = []
# The roster's guild information text, which GuildInfoFrame edits.
var _info_text: String = ""
# MSG_GUILD_EVENT_LOG_QUERY entries oldest first, each {type, player, other, rank, seconds}.
var _events: Array[Dictionary] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for i: int in ROWS:
		var row: BaseButton = get_node("%%FriendsFrameFriendsScrollFrameButton%d" % (i + 1))
		row.pressed.connect(_on_row_pressed.bind(i))
	for i: int in IGNORE_ROWS:
		var row: BaseButton = get_node("%%FriendsFrameIgnoreButton%d" % (i + 1))
		row.pressed.connect(_on_row_pressed.bind(i))
	%FriendsFrameCloseButton.pressed.connect(close_requested.emit)
	# The right-click menu's anchor frame, which the stock client never draws.
	%FriendsDropDown.hide()
	%FriendsFrameTab1.pressed.connect(show_tab.bind(Tab.FRIENDS))
	%FriendsFrameTab2.pressed.connect(show_tab.bind(Tab.WHO))
	%FriendsTabHeaderTab1.pressed.connect(show_tab.bind(Tab.FRIENDS))
	%FriendsTabHeaderTab2.pressed.connect(show_tab.bind(Tab.IGNORE))
	# Battle.net pending invites do not exist on this server.
	%FriendsTabHeaderTab3.hide()
	(%WhoFrame as WhoFrame).friend_requested.connect(_on_who_friend_requested)
	%FriendsFrameTab3.pressed.connect(show_tab.bind(Tab.GUILD))
	%FriendsFrameTab5.pressed.connect(show_tab.bind(Tab.RAID))
	# The Chat tab's channel list is not ported.
	%FriendsFrameTab4.hide()
	PanelManager.chain_tabs(
		[%FriendsFrameTab1, %FriendsFrameTab2, %FriendsFrameTab3, %FriendsFrameTab5], TAB_OVERLAP
	)
	%FriendsFrameAddFriendButton.pressed.connect(
		func() -> void: name_requested.emit(_tab)
	)
	%GuildFrameAddMemberButton.pressed.connect(
		func() -> void: name_requested.emit(Tab.GUILD)
	)
	%FriendsFrameUnsquelchButton.pressed.connect(_remove_selected)
	%GuildFrameGuildInformationButton.pressed.connect(_toggle_popup.bind(%GuildInfoFrame))
	%GuildInfoGuildEventButton.pressed.connect(_toggle_popup.bind(%GuildEventLogFrame))
	%GuildInfoCancelButton.pressed.connect(%GuildInfoFrame.hide)
	%GuildInfoCloseButton.pressed.connect(%GuildInfoFrame.hide)
	%GuildEventLogCancelButton.pressed.connect(%GuildEventLogFrame.hide)
	%GuildEventLogCloseButton.pressed.connect(%GuildEventLogFrame.hide)
	%GuildInfoSaveButton.pressed.connect(_save_guild_info)
	var session: WowSession = WowClient.session
	session.packet_received.connect(_on_packet_received)
	session.name_received.connect(_on_name_received)
	hide()


func show_tab(tab: Tab) -> void:
	_tab = tab
	_selected = -1
	%FriendsTabHeader.visible = tab in [Tab.FRIENDS, Tab.IGNORE]
	%FriendsListFrame.visible = tab == Tab.FRIENDS
	%IgnoreListFrame.visible = tab == Tab.IGNORE
	%GuildFrame.visible = tab == Tab.GUILD
	%RaidFrame.visible = tab == Tab.RAID
	%WhoFrame.visible = tab == Tab.WHO
	if tab == Tab.GUILD:
		request_roster()
	elif tab in [Tab.FRIENDS, Tab.IGNORE]:
		request_lists()
	refresh()


# CMSG_GUILD_ROSTER answers with the members, the ranks and the message of the day.
func request_roster() -> void:
	WowClient.session.send_packet("CMSG_GUILD_ROSTER", PackedByteArray())


func accept_guild_invite() -> void:
	WowClient.session.send_packet("CMSG_GUILD_ACCEPT", PackedByteArray())


func decline_guild_invite() -> void:
	WowClient.session.send_packet("CMSG_GUILD_DECLINE", PackedByteArray())


# Friend, ignore and guild commands all carry one string, or nothing at all.
static func send_command(opcode: String, text: String = "") -> void:
	var payload: PackedByteArray = []
	if not text.is_empty():
		payload = text.to_utf8_buffer()
		payload.append(0)
	WowClient.session.send_packet(opcode, payload)


# CMSG_FRIEND_LIST answers with both lists, so opening the window asks once.
func request_lists() -> void:
	if not PacketReader.wotlk:
		WowClient.session.send_packet("CMSG_FRIEND_LIST", PackedByteArray())
		return
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_u32(0, CONTACT_FRIEND | CONTACT_IGNORED)
	WowClient.session.send_packet("CMSG_CONTACT_LIST", payload)


func _on_who_friend_requested(player_name: String) -> void:
	send_command("CMSG_ADD_FRIEND", player_name)


func add(player_name: String) -> void:
	if _tab == Tab.GUILD:
		send_command("CMSG_GUILD_INVITE", player_name)
		return
	send_command("CMSG_ADD_FRIEND" if _tab == Tab.FRIENDS else "CMSG_ADD_IGNORE", player_name)


func refresh() -> void:
	if _tab == Tab.GUILD:
		_refresh_guild()
		return
	if _tab == Tab.RAID:
		%FriendsFrameTitleText.text = WowStrings.get_text("RAID")
		(%RaidFrame as RaidFrame).refresh()
		return
	if _tab == Tab.WHO:
		%FriendsFrameTitleText.text = WowStrings.get_text("WHO_LIST")
		return
	%FriendsFrameTitleText.text = WowStrings.get_text(
		"FRIENDS_LIST" if _tab == Tab.FRIENDS else "IGNORE_LIST"
	)
	var session: WowSession = WowClient.session
	if _tab == Tab.IGNORE:
		for i: int in IGNORE_ROWS:
			var row: Control = get_node("%%FriendsFrameIgnoreButton%d" % (i + 1))
			row.visible = i < _ignored.size()
			if row.visible:
				var text: Label = get_node("%%FriendsFrameIgnoreButton%dName" % (i + 1))
				text.text = session.get_object_name(_ignored[i])
		return
	for i: int in ROWS:
		var row: Control = get_node("%%FriendsFrameFriendsScrollFrameButton%d" % (i + 1))
		row.visible = i < _friends.size()
		if not row.visible:
			continue
		var entry: Dictionary = _friends[i]
		var text: Label = get_node("%%FriendsFrameFriendsScrollFrameButton%dName" % (i + 1))
		var info: Label = get_node("%%FriendsFrameFriendsScrollFrameButton%dInfo" % (i + 1))
		text.text = session.get_object_name(entry["guid"])
		info.text = WowStrings.get_text("FRIENDS_LIST_ONLINE", "Online") \
		if entry["online"] else WowStrings.get_text("FRIENDS_LIST_OFFLINE", "Offline")


func is_ignored(guid: int) -> bool:
	return guid in _ignored


func _refresh_guild() -> void:
	%FriendsFrameTitleText.text = _guild_name
	var online: int = _members.reduce(
		func(count: int, member: Dictionary) -> int: return count + int(member["online"]), 0
	)
	(%GuildFrameTotals as Label).text = WowStrings.strip_colors(
		WowStrings.get_text("GUILD_TOTAL" if _members.size() == 1 else "GUILD_TOTAL_P1", "%d")
	) % _members.size()
	(%GuildFrameOnlineTotals as Label).text = WowStrings.strip_colors(
		WowStrings.get_text("GUILD_TOTALONLINE", "(%d online)")
	) % online
	for i: int in GUILD_ROWS:
		var row: Control = get_node("%%GuildFrameButton%d" % (i + 1))
		row.visible = i < _members.size()
		if not row.visible:
			continue
		var member: Dictionary = _members[i]
		row.modulate = Color.WHITE if member["online"] else Color(0.5, 0.5, 0.5)
		(get_node("%%GuildFrameButton%dName" % (i + 1)) as Label).text = member["name"]
		(get_node("%%GuildFrameButton%dLevel" % (i + 1)) as Label).text = str(member["level"])
		(get_node("%%GuildFrameButton%dClass" % (i + 1)) as Label).text = \
			CharacterOptions.class_label(member["class"])
		(get_node("%%GuildFrameButton%dZone" % (i + 1)) as Label).text = \
			AreaInfo.area_name(member["zone"]) if member["online"] else ""


func _on_row_pressed(index: int) -> void:
	_selected = index


# Friends leave through the stock right-click menu, which is not ported.
func _remove_selected() -> void:
	if _tab != Tab.IGNORE or _selected < 0 or _selected >= _ignored.size():
		return
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, _ignored[_selected])
	WowClient.session.send_packet("CMSG_DEL_IGNORE", payload)


# What the guild's tabard is set to, empty until its query has answered.
func emblem() -> PackedInt32Array:
	return _emblem


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_FRIEND_LIST":
			_friends.clear()
			for i: int in reader.u8():
				var entry: Dictionary = {"guid": reader.u64(), "online": reader.u8() != 0}
				if entry["online"]:
					entry["area"] = reader.u32()
					entry["level"] = reader.u32()
					entry["class"] = reader.u32()
				_friends.append(entry)
				WowClient.session.get_object_name(entry["guid"])
			refresh()
		"SMSG_CONTACT_LIST":
			_read_contacts(reader)
		"SMSG_IGNORE_LIST":
			_ignored.clear()
			for i: int in reader.u8():
				var guid: int = reader.u64()
				_ignored.append(guid)
				WowClient.session.get_object_name(guid)
			refresh()
		"SMSG_FRIEND_STATUS":
			_on_status(reader)
		"SMSG_GUILD_ROSTER":
			_on_roster(reader)
		"SMSG_GUILD_QUERY_RESPONSE":
			reader.u32()
			_guild_name = reader.cstring()
			_read_emblem(reader)
			if _tab == Tab.GUILD:
				_refresh_guild()
		"SMSG_GUILD_INVITE":
			guild_invited.emit(reader.cstring(), reader.cstring())
		"SMSG_GUILD_EVENT":
			_on_guild_event(reader)
		"SMSG_GUILD_COMMAND_RESULT":
			_on_guild_result(reader)
		"MSG_GUILD_EVENT_LOG_QUERY":
			_read_events(reader)


# The ignore list only comes at login, so its changes are followed here.
func _on_status(reader: PacketReader) -> void:
	var result: Result = reader.u8() as Result
	var guid: int = reader.u64()
	if result == Result.IGNORE_ADDED and not _ignored.has(guid):
		_ignored.append(guid)
	elif result == Result.IGNORE_REMOVED:
		_ignored.erase(guid)
	var key: String = STATUS_MESSAGES.get(result, "")
	if not key.is_empty():
		var player_name: String = WowClient.session.get_object_name(guid)
		if player_name.is_empty():
			# The name query is still out; the line waits for it rather than naming nobody.
			_awaiting_name[guid] = key
		else:
			message_added.emit(_line(key, player_name))
	request_lists()


# 3.3.5 sends friends and ignores as one list, each contact flagged with what it is.
func _read_contacts(reader: PacketReader) -> void:
	_friends.clear()
	_ignored.clear()
	reader.u32()
	for i: int in reader.u32():
		var guid: int = reader.u64()
		var flags: int = reader.u32()
		reader.cstring()
		WowClient.session.get_object_name(guid)
		if flags & CONTACT_IGNORED:
			_ignored.append(guid)
		if flags & CONTACT_FRIEND == 0:
			continue
		var entry: Dictionary = {"guid": guid, "online": reader.u8() != 0}
		if entry["online"]:
			entry["area"] = reader.u32()
			entry["level"] = reader.u32()
			entry["class"] = reader.u32()
		_friends.append(entry)
	refresh()


# The roster names every member, their rank and, for those online, where they are.
func _on_roster(reader: PacketReader) -> void:
	var count: int = reader.u32()
	(%GuildFrameNotesText as Label).text = reader.cstring()
	_info_text = reader.cstring()
	for i: int in reader.u32():
		for word: int in WOTLK_RANK_WORDS if PacketReader.wotlk else 1:
			reader.u32()
	_members.clear()
	for i: int in count:
		var member: Dictionary = {"guid": reader.u64(), "online": reader.u8() != 0}
		member["name"] = reader.cstring()
		member["rank"] = reader.u32()
		member["level"] = reader.u8()
		member["class"] = reader.u8()
		if PacketReader.wotlk:
			reader.u8()
		member["zone"] = reader.u32()
		if not member["online"]:
			member["days_offline"] = reader.f32()
		member["note"] = reader.cstring()
		member["officer_note"] = reader.cstring()
		_members.append(member)
	if _guild_name.is_empty():
		_query_guild()
	if _tab == Tab.GUILD:
		_refresh_guild()


# Only the query answers with the guild's name, which titles the window.
func _query_guild() -> void:
	var session: WowSession = WowClient.session
	var guild_id: int = session.get_field(session.get_player_guid(), "PLAYER_GUILDID")
	if guild_id == 0:
		return
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_u32(0, guild_id)
	session.send_packet("CMSG_GUILD_QUERY", payload)


# The ten rank names come before the five numbers a tabard vendor saved on the guild.
func _read_emblem(reader: PacketReader) -> void:
	_rank_names.clear()
	for rank: int in GUILD_RANKS:
		_rank_names.append(reader.cstring())
	_emblem = PackedInt32Array()
	for part: int in TabardFrame.Part.size():
		_emblem.append(reader.u32())


func _on_guild_event(reader: PacketReader) -> void:
	var event: GuildEvent = reader.u8() as GuildEvent
	var params: PackedStringArray = []
	for i: int in reader.u8():
		params.append(reader.cstring())
	if event == GuildEvent.LEADER_CHANGED and params.size() > 1:
		params = params.slice(1)
	if GUILD_MESSAGES.has(event):
		message_added.emit(_fill(WowStrings.get_text(GUILD_MESSAGES[event], ""), params))
	if _tab == Tab.GUILD:
		request_roster()


func _on_guild_result(reader: PacketReader) -> void:
	reader.u32()
	var text: String = reader.cstring()
	var result: GuildResult = reader.u32() as GuildResult
	if not GUILD_ERRORS.has(result):
		return
	message_added.emit(_fill(
		WowStrings.get_text(GUILD_ERRORS[result], ""), PackedStringArray([text])
	))


# ERR_FRIEND_ONLINE_SS wants the name twice, so a short list repeats its last entry.
func _fill(text: String, params: PackedStringArray) -> String:
	var filled: Array[String] = []
	for i: int in text.count("%s"):
		if params.is_empty():
			return text
		filled.append(params[mini(i, params.size() - 1)])
	return text % filled if not filled.is_empty() else text


func _line(key: String, player_name: String) -> String:
	var text: String = WowStrings.get_text(key, "%s")
	return text % player_name if text.count("%s") == 1 else text


func _on_name_received(guid: int, player_name: String) -> void:
	if _awaiting_name.has(guid):
		message_added.emit(_line(_awaiting_name[guid], player_name))
		_awaiting_name.erase(guid)
	refresh()
	_write_events()


# GuildFramePopup_Show: one guild popup at a time.
func _toggle_popup(popup: Control) -> void:
	var showing: bool = not popup.visible
	for other: CanvasItem in [
		%GuildEventLogFrame, %GuildInfoFrame, %GuildMemberDetailFrame, %GuildControlPopupFrame,
	]:
		other.hide()
	popup.visible = showing
	if not showing:
		return
	if popup == %GuildInfoFrame:
		(%GuildInfoEditBox as TextEdit).text = _info_text
	else:
		WowClient.session.send_packet("MSG_GUILD_EVENT_LOG_QUERY", PackedByteArray())


# GuildInfoSaveButton's OnClick keeps the new text until the next roster brings it back.
func _save_guild_info() -> void:
	_info_text = (%GuildInfoEditBox as TextEdit).text
	var payload: PackedByteArray = _info_text.to_utf8_buffer()
	payload.append(0)
	WowClient.session.send_packet("CMSG_GUILD_INFO_TEXT", payload)
	request_roster()
	%GuildInfoFrame.hide()


# GuildEventLogTypes; joins and leaves name no second player, promotions and demotions add a rank.
func _read_events(reader: PacketReader) -> void:
	_events.clear()
	for i: int in reader.u8():
		var event: Dictionary = {"type": reader.u8() as EventLogType, "player": reader.u64()}
		if event["type"] not in [EventLogType.JOIN, EventLogType.QUIT]:
			event["other"] = reader.u64()
		if event["type"] in [EventLogType.PROMOTE, EventLogType.DEMOTE]:
			event["rank"] = reader.u8()
		event["seconds"] = reader.u32()
		_events.push_front(event)
	_write_events()


# GuildEventLog_Update.
func _write_events() -> void:
	if not %GuildEventLogFrame.visible:
		return
	var lines: PackedStringArray = []
	for event: Dictionary in _events:
		var names: Array = [_event_name(event["player"]), _event_name(event.get("other", 0))]
		var rank: int = event.get("rank", 0)
		names.append(_rank_names[rank] if rank < _rank_names.size() else "")
		var ago: String = WowStrings.format(WowStrings.get_text("GUILD_BANK_LOG_TIME"),
				[GuildBankFrame.time_ago(event["seconds"])])
		lines.append(WowStrings.format(WowStrings.get_text(EVENT_LOG_TEXT[event["type"]]), names)
				+ "   " + ago)
	(%GuildEventMessage as Label).text = "\n".join(lines)


func _event_name(guid: int) -> String:
	var player_name: String = WowClient.session.get_object_name(guid) if guid else ""
	return player_name if player_name else WowStrings.get_text("UNKNOWN")
