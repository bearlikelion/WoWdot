class_name PartyFrame
extends Control

signal invited(inviter: String)
signal message_added(text: String)
signal error_raised(text: String)
signal unit_selected(guid: int)
signal unit_menu_requested(guid: int)
signal ready_check_started
signal raid_changed
signal target_icons_changed

enum LootMethod { FREE_FOR_ALL, ROUND_ROBIN, MASTER_LOOT, GROUP_LOOT, NEED_BEFORE_GREED }
# The eight marks a raid leader can hang on a target, in the order the wire numbers them.
enum TargetIcon { STAR, CIRCLE, DIAMOND, TRIANGLE, MOON, SQUARE, CROSS, SKULL }

const READY_YES: String = "%s is ready."
const READY_NO: String = "%s is not ready."
const MAX_MEMBERS: int = 4
# GROUP_UPDATE_FLAG bits in order, as far as the bars need them.
const STAT_FIELDS: PackedStringArray = [
	"status", "health", "max_health", "power_type", "power", "max_power",
]
const BYTE_STATS: PackedStringArray = ["status", "power_type"]
const MAX_RAID_MEMBERS: int = 40
# A member's subgroup sits in the low bits of its flag byte, with assistant in the top one.
const SUBGROUP_MASK: int = 0x0F
const ASSISTANT_FLAG: int = 0x80
static var RAID_FLAG: int = 0x02 if PacketReader.wotlk else 0x01
const LFG_FLAG: int = 0x08
const WOTLK_ASSISTANT_FLAG: int = 0x01
const WOTLK_RESULTS: Dictionary[int, String] = {
	1: "ERR_BAD_PLAYER_NAME_S", 2: "ERR_TARGET_NOT_IN_GROUP_S", 3: "ERR_TARGET_NOT_IN_INSTANCE_S",
	4: "ERR_GROUP_FULL", 5: "ERR_ALREADY_IN_GROUP_S", 6: "ERR_NOT_IN_GROUP", 7: "ERR_NOT_LEADER",
	8: "ERR_PLAYER_WRONG_FACTION", 9: "ERR_IGNORING_YOU_S",
}
# MSG_RAID_TARGET_UPDATE: this icon asks for the whole list instead of setting one.
const ICON_REQUEST: int = 0xFF
const OPERATION_INVITE: int = 0
# SMSG_PARTY_COMMAND_RESULT codes after 0; those ending in _S name the player.
const RESULTS: Dictionary[int, String] = {
	1: "ERR_BAD_PLAYER_NAME_S", 2: "ERR_TARGET_NOT_IN_GROUP_S", 3: "ERR_GROUP_FULL",
	4: "ERR_ALREADY_IN_GROUP_S", 5: "ERR_NOT_IN_GROUP", 6: "ERR_NOT_LEADER",
	7: "ERR_PLAYER_WRONG_FACTION", 8: "ERR_IGNORING_YOU_S",
}

# The other members, each a name, guid, online flag, subgroup and assistant flag.
static var members: Array[Dictionary] = []
static var leader: int = 0
## Set once the party has been made a raid, which is what allows subgroups and target icons.
static var is_raid: bool = false
## The player's own subgroup, counted from zero as the wire does.
static var own_subgroup: int = 0
## Marked targets: icon index 0 to 7 against the guid wearing it.
static var target_icons: Dictionary[int, int] = {}

var _frames: Array[PartyMemberFrame] = []
var _remote_stats: Dictionary[int, Dictionary] = {}


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
	is_raid = false
	target_icons.clear()
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
	var payload: PackedByteArray = player_name.to_utf8_buffer()
	payload.append(0)
	if PacketReader.wotlk:
		payload.resize(payload.size() + 4)
	WowClient.session.send_packet("CMSG_GROUP_INVITE", payload)


static func uninvite(player_name: String) -> void:
	_send_name("CMSG_GROUP_UNINVITE", player_name)


static func accept() -> void:
	var payload: PackedByteArray = []
	if PacketReader.wotlk:
		payload.resize(4)
	WowClient.session.send_packet("CMSG_GROUP_ACCEPT", payload)


static func decline() -> void:
	WowClient.session.send_packet("CMSG_GROUP_DECLINE", PackedByteArray())


# LeaveParty: the server calls it disbanding, even for one member walking out.
# An empty MSG_RAID_READY_CHECK asks the party, and one with a state answers it.
static func start_ready_check() -> void:
	WowClient.session.send_packet("MSG_RAID_READY_CHECK", PackedByteArray())


static func answer_ready_check(is_ready: bool) -> void:
	WowClient.session.send_packet("MSG_RAID_READY_CHECK", PackedByteArray([1 if is_ready else 0]))


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


static func convert_to_raid() -> void:
	WowClient.session.send_packet("CMSG_GROUP_RAID_CONVERT", PackedByteArray())


# Subgroups are counted from zero on the wire, though the stock UI calls the first one group 1.
static func move_to_subgroup(player_name: String, subgroup: int) -> void:
	var payload: PackedByteArray = player_name.to_utf8_buffer()
	payload.append(0)
	payload.append(subgroup)
	WowClient.session.send_packet("CMSG_GROUP_CHANGE_SUB_GROUP", payload)


static func swap_subgroups(first_name: String, second_name: String) -> void:
	var payload: PackedByteArray = first_name.to_utf8_buffer()
	payload.append(0)
	payload.append_array(second_name.to_utf8_buffer())
	payload.append(0)
	WowClient.session.send_packet("CMSG_GROUP_SWAP_SUB_GROUP", payload)


# 1.12 names the member by guid here, where the earlier builds sent the name.
static func set_assistant(guid: int, assisting: bool) -> void:
	var payload: PackedByteArray = []
	payload.resize(9)
	payload.encode_u64(0, guid)
	payload.encode_u8(8, int(assisting))
	WowClient.session.send_packet("CMSG_GROUP_ASSISTANT_LEADER", payload)


static func set_leader(guid: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, guid)
	WowClient.session.send_packet("CMSG_GROUP_SET_LEADER", payload)


static func set_target_icon(icon: TargetIcon, guid: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(9)
	payload.encode_u8(0, icon)
	payload.encode_u64(1, guid)
	WowClient.session.send_packet("MSG_RAID_TARGET_UPDATE", payload)


static func request_target_icons() -> void:
	WowClient.session.send_packet("MSG_RAID_TARGET_UPDATE", PackedByteArray([ICON_REQUEST]))


static func subgroup_of(guid: int) -> int:
	for member: Dictionary in members:
		if member["guid"] == guid:
			return member["subgroup"]
	return own_subgroup if guid == WowClient.session.get_player_guid() else -1


static func is_assistant(guid: int) -> bool:
	for member: Dictionary in members:
		if member["guid"] == guid:
			return member["assistant"]
	return false


static func _send_name(opcode: String, player_name: String) -> void:
	var payload: PackedByteArray = player_name.to_utf8_buffer()
	payload.append(0)
	WowClient.session.send_packet(opcode, payload)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	match opcode:
		"SMSG_GROUP_INVITE":
			invited.emit(_string_at(payload, 1 if PacketReader.wotlk else 0))
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
		"MSG_RAID_READY_CHECK_FINISHED":
			message_added.emit(WowStrings.get_text("READY_CHECK_FINISHED", "Ready check complete."))
		"MSG_RAID_READY_CHECK_CONFIRM":
			_on_ready_answer(PacketReader.new(payload))
		"MSG_RAID_TARGET_UPDATE":
			_on_target_icons(payload)
		"SMSG_PARTY_MEMBER_STATS":
			_on_member_stats(PacketReader.new(payload))
		"SMSG_PARTY_MEMBER_STATS_FULL":
			var reader: PacketReader = PacketReader.new(payload)
			if PacketReader.wotlk:
				reader.u8()
			_on_member_stats(reader)


# Members out of sight have no object, so the server reports their bars; the mask picks the fields.
func _on_member_stats(reader: PacketReader) -> void:
	var member: int = reader.packed_guid()
	var mask: int = reader.u32()
	var stats: Dictionary = _remote_stats.get_or_add(member, {})
	for i: int in STAT_FIELDS.size():
		if mask & (1 << i):
			stats[STAT_FIELDS[i]] = _read_stat(reader, STAT_FIELDS[i])
	_refresh()


# 3.3.5 widened the status to a word and the health pair to double words.
func _read_stat(reader: PacketReader, field: String) -> int:
	if PacketReader.wotlk:
		if field == "status":
			return reader.u16()
		if field == "health" or field == "max_health":
			return reader.u32()
	return reader.u8() if field in BYTE_STATS else reader.u16()


func _on_ready_check(payload: PackedByteArray) -> void:
	if payload.is_empty() or PacketReader.wotlk:
		ready_check_started.emit()
		return
	_on_ready_answer(PacketReader.new(payload))


func _on_ready_answer(reader: PacketReader) -> void:
	var member: String = WowClient.session.get_object_name(reader.u64())
	var is_ready: bool = reader.u8() != 0
	# 1.12 has no ready check of its own, so these lines carry their own words.
	message_added.emit((READY_YES if is_ready else READY_NO) % member)


# Deferred so each frame has dropped a destroyed member before it is shown again by name.
func _on_objects_changed() -> void:
	_refresh.call_deferred()


func _on_list_received(payload: PackedByteArray) -> void:
	var before: Array[Dictionary] = members.duplicate()
	var was_raid: bool = is_raid
	members.clear()
	var group_type: int = payload.decode_u8(0)
	is_raid = group_type & RAID_FLAG != 0
	own_subgroup = payload.decode_u8(1) & SUBGROUP_MASK
	var offset: int = 6
	if PacketReader.wotlk:
		# Member flags, roles, an LFG block, the group guid and a counter precede the count.
		offset = 20 if group_type & LFG_FLAG == 0 else 25
	for i: int in payload.decode_u32(offset - 4):
		var member_name: String = _string_at(payload, offset)
		offset += member_name.to_utf8_buffer().size() + 1
		var flags: int = payload.decode_u8(offset + 9)
		var assistant: bool = flags & ASSISTANT_FLAG != 0
		if PacketReader.wotlk:
			assistant = payload.decode_u8(offset + 10) & WOTLK_ASSISTANT_FLAG != 0
		members.append({
			"name": member_name,
			"guid": payload.decode_u64(offset),
			"online": payload.decode_u8(offset + 8) & 1 != 0,
			"subgroup": flags & SUBGROUP_MASK,
			"assistant": assistant,
		})
		offset += 12 if PacketReader.wotlk else 10
	leader = payload.decode_u64(offset) if offset + 8 <= payload.size() else 0
	if members.is_empty():
		is_raid = false
		target_icons.clear()
	if is_raid != was_raid:
		raid_changed.emit()
	_announce_changes(before)
	for member: Dictionary in members:
		var ask: PackedByteArray = []
		ask.resize(8)
		ask.encode_u64(0, member["guid"])
		WowClient.session.send_packet("CMSG_REQUEST_PARTY_MEMBER_STATS", ask)
	_refresh()


# Mode 0 carries one changed mark, mode 1 the whole set after a request or a group list reset.
func _on_target_icons(payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	if reader.u8() == 0:
		if PacketReader.wotlk:
			reader.u64()
		var icon: int = reader.u8()
		var guid: int = reader.u64()
		if guid == 0:
			target_icons.erase(icon)
		else:
			target_icons[icon] = guid
	else:
		target_icons.clear()
		while true:
			var icon: int = reader.u8()
			var guid: int = reader.u64()
			if guid == 0:
				break
			target_icons[icon] = guid
	target_icons_changed.emit()


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
	var results: Dictionary[int, String] = WOTLK_RESULTS if PacketReader.wotlk else RESULTS
	if results.has(result):
		error_raised.emit(_format(results[result], player_name))


func _refresh() -> void:
	for i: int in MAX_MEMBERS:
		var member: Dictionary = members[i] if i < members.size() else {}
		_frames[i].remote_stats = _remote_stats.get(member.get("guid", 0), {})
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
