class_name PartyFrame
extends Control

signal invited(inviter: String)
signal message_added(text: String)
signal error_raised(text: String)
signal unit_selected(guid: int)
signal unit_menu_requested(guid: int)
signal ready_check_started

enum LootMethod { FREE_FOR_ALL, ROUND_ROBIN, MASTER_LOOT, GROUP_LOOT, NEED_BEFORE_GREED }

const READY_YES: String = "%s is ready."
const READY_NO: String = "%s is not ready."
const MAX_MEMBERS: int = 4
const OPERATION_INVITE: int = 0
# SMSG_PARTY_COMMAND_RESULT codes after 0; those ending in _S name the player.
const RESULTS: Dictionary[int, String] = {
	1: "ERR_BAD_PLAYER_NAME_S", 2: "ERR_TARGET_NOT_IN_GROUP_S", 3: "ERR_GROUP_FULL",
	4: "ERR_ALREADY_IN_GROUP_S", 5: "ERR_NOT_IN_GROUP", 6: "ERR_NOT_LEADER",
	7: "ERR_PLAYER_WRONG_FACTION", 8: "ERR_IGNORING_YOU_S",
}

# The other members, each a name, guid and online flag, as SMSG_GROUP_LIST last sent them.
static var members: Array[Dictionary] = []
static var leader: int = 0

var _frames: Array[PartyMemberFrame] = []


func _ready() -> void:
	for i: int in MAX_MEMBERS:
		var frame: PartyMemberFrame = get_node("%%PartyMemberFrame%d" % (i + 1))
		frame.unit_selected.connect(unit_selected.emit)
		frame.unit_menu_requested.connect(unit_menu_requested.emit)
		_frames.append(frame)
	var session: WowSession = WowClient.session
	session.packet_received.connect(_on_packet_received)
	session.object_created.connect(_on_objects_changed.unbind(2))
	session.objects_destroyed.connect(_on_objects_changed.unbind(1))
	members.clear()
	leader = 0
	_refresh()


static func in_party() -> bool:
	return not members.is_empty()


static func is_leader() -> bool:
	return leader == WowClient.session.get_player_guid()


static func has_member(member_name: String) -> bool:
	for member: Dictionary in members:
		if (member["name"] as String).nocasecmp_to(member_name) == 0:
			return true
	return false


static func invite(player_name: String) -> void:
	_send_name("CMSG_GROUP_INVITE", player_name)


static func uninvite(player_name: String) -> void:
	_send_name("CMSG_GROUP_UNINVITE", player_name)


static func accept() -> void:
	WowClient.session.send_packet("CMSG_GROUP_ACCEPT", PackedByteArray())


static func decline() -> void:
	WowClient.session.send_packet("CMSG_GROUP_DECLINE", PackedByteArray())


# LeaveParty: the server calls it disbanding, even for one member walking out.
# An empty MSG_RAID_READY_CHECK asks the party, and one with a state answers it.
static func start_ready_check() -> void:
	WowClient.session.send_packet("MSG_RAID_READY_CHECK", PackedByteArray())


static func answer_ready_check(ready: bool) -> void:
	WowClient.session.send_packet("MSG_RAID_READY_CHECK", PackedByteArray([1 if ready else 0]))


# CMSG_LOOT_METHOD: how the party shares loot, and the quality that starts a roll.
static func set_loot_method(method: LootMethod, threshold: int, master: int = 0) -> void:
	var payload: PackedByteArray = []
	payload.resize(16)
	payload.encode_u32(0, method)
	payload.encode_u64(4, master)
	payload.encode_u32(12, threshold)
	WowClient.session.send_packet("CMSG_LOOT_METHOD", payload)


static func leave() -> void:
	WowClient.session.send_packet("CMSG_GROUP_DISBAND", PackedByteArray())


static func _send_name(opcode: String, player_name: String) -> void:
	var payload: PackedByteArray = player_name.to_utf8_buffer()
	payload.append(0)
	WowClient.session.send_packet(opcode, payload)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	match opcode:
		"SMSG_GROUP_INVITE":
			invited.emit(_string_at(payload, 0))
		"SMSG_GROUP_LIST":
			_on_list_received(payload)
		"SMSG_GROUP_DECLINE":
			_say("ERR_DECLINE_GROUP_S", _string_at(payload, 0))
		"SMSG_GROUP_UNINVITE":
			_say("ERR_UNINVITE_YOU")
		"SMSG_GROUP_DESTROYED":
			_say("ERR_GROUP_DISBANDED")
		"SMSG_GROUP_SET_LEADER":
			_say("ERR_NEW_LEADER_S", _string_at(payload, 0))
		"SMSG_PARTY_COMMAND_RESULT":
			_on_result_received(payload)
		"MSG_RAID_READY_CHECK":
			_on_ready_check(payload)


func _on_ready_check(payload: PackedByteArray) -> void:
	if payload.is_empty():
		ready_check_started.emit()
		return
	var reader: PacketReader = PacketReader.new(payload)
	var member: String = WowClient.session.get_object_name(reader.u64())
	var ready: bool = reader.u8() != 0
	# 1.12 has no ready check of its own, so these lines carry their own words.
	message_added.emit((READY_YES if ready else READY_NO) % member)


# Deferred so each frame has dropped a destroyed member before it is shown again by name.
func _on_objects_changed() -> void:
	_refresh.call_deferred()


func _on_list_received(payload: PackedByteArray) -> void:
	var before: Array[Dictionary] = members.duplicate()
	members.clear()
	var offset: int = 6
	for i: int in payload.decode_u32(2):
		var member_name: String = _string_at(payload, offset)
		offset += member_name.to_utf8_buffer().size() + 1
		members.append({
			"name": member_name,
			"guid": payload.decode_u64(offset),
			"online": payload.decode_u8(offset + 8) & 1 != 0,
		})
		offset += 10
	leader = payload.decode_u64(offset) if offset + 8 <= payload.size() else 0
	_announce_changes(before)
	_refresh()


func _announce_changes(before: Array[Dictionary]) -> void:
	var was: PackedStringArray = []
	for member: Dictionary in before:
		was.append(member["name"])
		if not has_member(member["name"]) and in_party():
			_say("ERR_LEFT_GROUP_S", member["name"])
	for member: Dictionary in members:
		if not before.is_empty() and not was.has(member["name"]):
			_say("ERR_JOINED_GROUP_S", member["name"])
	if members.is_empty() and not before.is_empty():
		_say("ERR_LEFT_GROUP_YOU")


func _on_result_received(payload: PackedByteArray) -> void:
	var operation: int = payload.decode_u32(0)
	var player_name: String = _string_at(payload, 4)
	var result: int = payload.decode_u32(4 + player_name.to_utf8_buffer().size() + 1)
	if result == 0:
		if operation == OPERATION_INVITE:
			_say("ERR_INVITE_PLAYER_S", player_name)
		return
	if RESULTS.has(result):
		error_raised.emit(_format(RESULTS[result], player_name))


func _refresh() -> void:
	for i: int in MAX_MEMBERS:
		var member: Dictionary = members[i] if i < members.size() else {}
		_frames[i].show_member(member, not member.is_empty() and member["guid"] == leader)


func _say(key: String, player_name: String = "") -> void:
	message_added.emit(_format(key, player_name))


func _format(key: String, player_name: String) -> String:
	var text: String = WowStrings.get_text(key)
	return text % player_name if text.contains("%s") else text


func _string_at(payload: PackedByteArray, offset: int) -> String:
	var end: int = payload.find(0, offset)
	if end < 0:
		end = payload.size()
	return payload.slice(offset, end).get_string_from_utf8()
