@tool
class_name FriendsFrame
extends Control

signal close_requested
signal name_requested(add_friend: bool)
signal message_added(text: String)

enum Tab { FRIENDS, IGNORE }

const ROWS: int = 10
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

var _tab: Tab = Tab.FRIENDS
var _friends: Array[Dictionary] = []
var _ignored: Array[int] = []
var _selected: int = -1
var _awaiting_name: Dictionary[int, String] = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for i: int in ROWS:
		var row: BaseButton = get_node("%%FriendsFrameFriendButton%d" % (i + 1))
		row.pressed.connect(_on_row_pressed.bind(i))
	%FriendsFrameCloseButton.pressed.connect(close_requested.emit)
	%FriendsFrameTab1.pressed.connect(show_tab.bind(Tab.FRIENDS))
	%FriendsFrameTab2.pressed.connect(show_tab.bind(Tab.IGNORE))
	%FriendsFrameAddFriendButton.pressed.connect(
		func() -> void: name_requested.emit(_tab == Tab.FRIENDS)
	)
	%FriendsFrameRemoveFriendButton.pressed.connect(_remove_selected)
	var session: WowSession = WowClient.session
	session.packet_received.connect(_on_packet_received)
	session.name_received.connect(_on_name_received)
	hide()


func show_tab(tab: Tab) -> void:
	_tab = tab
	_selected = -1
	request_lists()
	refresh()


# CMSG_FRIEND_LIST answers with both lists, so opening the window asks once.
func request_lists() -> void:
	WowClient.session.send_packet("CMSG_FRIEND_LIST", PackedByteArray())


func add(player_name: String) -> void:
	_send_name("CMSG_ADD_FRIEND" if _tab == Tab.FRIENDS else "CMSG_ADD_IGNORE", player_name)


func refresh() -> void:
	var session: WowSession = WowClient.session
	var rows: int = _friends.size() if _tab == Tab.FRIENDS else _ignored.size()
	for i: int in ROWS:
		var row: Control = get_node("%%FriendsFrameFriendButton%d" % (i + 1))
		row.visible = i < rows
		if not row.visible:
			continue
		var text: Label = get_node("%%FriendsFrameFriendButton%dButtonTextNameLocation" % (i + 1))
		var info: Label = get_node("%%FriendsFrameFriendButton%dButtonTextInfo" % (i + 1))
		if _tab == Tab.FRIENDS:
			var entry: Dictionary = _friends[i]
			text.text = session.get_object_name(entry["guid"])
			info.text = WowStrings.get_text("FRIENDS_LIST_ONLINE", "Online") \
			if entry["online"] else WowStrings.get_text("FRIENDS_LIST_OFFLINE", "Offline")
		else:
			text.text = session.get_object_name(_ignored[i])
			info.text = ""


func _on_row_pressed(index: int) -> void:
	_selected = index


func _remove_selected() -> void:
	var guid: int = 0
	if _tab == Tab.FRIENDS and _selected >= 0 and _selected < _friends.size():
		guid = _friends[_selected]["guid"]
	elif _tab == Tab.IGNORE and _selected >= 0 and _selected < _ignored.size():
		guid = _ignored[_selected]
	if guid == 0:
		return
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, guid)
	WowClient.session.send_packet(
		"CMSG_DEL_FRIEND" if _tab == Tab.FRIENDS else "CMSG_DEL_IGNORE", payload
	)


func _send_name(opcode: String, player_name: String) -> void:
	var payload: PackedByteArray = player_name.to_utf8_buffer()
	payload.append(0)
	WowClient.session.send_packet(opcode, payload)


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
		"SMSG_IGNORE_LIST":
			_ignored.clear()
			for i: int in reader.u8():
				var guid: int = reader.u64()
				_ignored.append(guid)
				WowClient.session.get_object_name(guid)
			refresh()
		"SMSG_FRIEND_STATUS":
			_on_status(reader)


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


func _line(key: String, player_name: String) -> String:
	var text: String = WowStrings.get_text(key, "%s")
	return text % player_name if text.count("%s") == 1 else text


func _on_name_received(guid: int, player_name: String) -> void:
	if _awaiting_name.has(guid):
		message_added.emit(_line(_awaiting_name[guid], player_name))
		_awaiting_name.erase(guid)
	refresh()
