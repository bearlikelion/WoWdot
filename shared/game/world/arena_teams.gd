class_name ArenaTeams
extends RefCounted

signal changed
signal invited(inviter: String, team_name: String)
signal message(text: String)

enum Info { ID, TYPE, MEMBER, GAMES_WEEK, GAMES_SEASON, WINS_SEASON, PERSONAL_RATING }

const SLOTS: int = 3
const INFO_FIELDS: int = 7
# ArenaTeamEvents to the GlobalStrings each formats with its names.
const EVENTS: Dictionary[int, String] = {
	3: "ERR_ARENA_TEAM_JOIN_SS",
	4: "ERR_ARENA_TEAM_LEAVE_SS",
	5: "ERR_ARENA_TEAM_REMOVE_SSS",
	6: "ERR_ARENA_TEAM_LEADER_IS_SS",
	7: "ERR_ARENA_TEAM_LEADER_CHANGED_SSS",
	8: "ERR_ARENA_TEAM_DISBANDED_S",
}
# ArenaTeamCommandErrors to their GlobalStrings; zero is success and says nothing.
const ERRORS: Dictionary[int, String] = {
	0x01: "ERR_ARENA_TEAM_INTERNAL",
	0x02: "ERR_ALREADY_IN_ARENA_TEAM",
	0x03: "ERR_ALREADY_IN_ARENA_TEAM_S",
	0x04: "ERR_INVITED_TO_ARENA_TEAM",
	0x05: "ERR_ALREADY_INVITED_TO_ARENA_TEAM_S",
	0x06: "ERR_ARENA_TEAM_NAME_INVALID",
	0x07: "ERR_ARENA_TEAM_NAME_EXISTS_S",
	0x08: "ERR_ARENA_TEAM_PERMISSIONS",
	0x09: "ERR_ARENA_TEAM_PLAYER_NOT_IN_TEAM",
	0x0A: "ERR_ARENA_TEAM_PLAYER_NOT_IN_TEAM_SS",
	0x0B: "ERR_ARENA_TEAM_PLAYER_NOT_FOUND_S",
	0x0C: "ERR_ARENA_TEAM_NOT_ALLIED",
	0x13: "ERR_ARENA_TEAM_IGNORING_YOU_S",
	0x15: "ERR_ARENA_TEAM_TARGET_TOO_LOW_S",
	0x16: "ERR_ARENA_TEAM_TARGET_TOO_HIGH_S",
	0x17: "ERR_ARENA_TEAM_TOO_MANY_MEMBERS_S",
	0x1B: "ERR_ARENA_TEAM_NOT_FOUND",
	0x1E: "ERR_ARENA_TEAMS_LOCKED",
}

# Team ids to what the server has said about them: {name, type, colours, stats, roster}.
var teams: Dictionary[int, Dictionary] = {}

var _session: WowSession


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)


# The player's own row of PLAYER_FIELD_ARENA_TEAM_INFO_1_1 for a slot, or {} when it is empty.
func slot_info(slot: int) -> Dictionary:
	var guid: int = _session.get_player_guid()
	var first: int = _session.field_index("PLAYER_FIELD_ARENA_TEAM_INFO_1_1") + slot * INFO_FIELDS
	var id: int = _session.get_field(guid, first + Info.ID)
	if id == 0:
		return {}
	var info: Dictionary = {}
	for field: Info in Info.values():
		info[field] = _session.get_field(guid, first + field)
	return info


func query(team_id: int) -> void:
	_send_id("CMSG_ARENA_TEAM_QUERY", team_id)


func request_roster(team_id: int) -> void:
	_send_id("CMSG_ARENA_TEAM_ROSTER", team_id)


func invite(team_id: int, player_name: String) -> void:
	_send_id_name("CMSG_ARENA_TEAM_INVITE", team_id, player_name)


func accept_invite() -> void:
	_session.send_packet("CMSG_ARENA_TEAM_ACCEPT", PackedByteArray())


func decline_invite() -> void:
	_session.send_packet("CMSG_ARENA_TEAM_DECLINE", PackedByteArray())


func leave(team_id: int) -> void:
	_send_id("CMSG_ARENA_TEAM_LEAVE", team_id)


func disband(team_id: int) -> void:
	_send_id("CMSG_ARENA_TEAM_DISBAND", team_id)


func remove(team_id: int, player_name: String) -> void:
	_send_id_name("CMSG_ARENA_TEAM_REMOVE", team_id, player_name)


func set_captain(team_id: int, player_name: String) -> void:
	_send_id_name("CMSG_ARENA_TEAM_LEADER", team_id, player_name)


func _send_id(opcode: String, team_id: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_u32(0, team_id)
	_session.send_packet(opcode, payload)


func _send_id_name(opcode: String, team_id: int, player_name: String) -> void:
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_u32(0, team_id)
	payload.append_array(player_name.to_utf8_buffer())
	payload.append(0)
	_session.send_packet(opcode, payload)


func _team(team_id: int) -> Dictionary:
	if not teams.has(team_id):
		teams[team_id] = {"roster": []}
	return teams[team_id]


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_ARENA_TEAM_QUERY_RESPONSE":
			var team: Dictionary = _team(reader.u32())
			team["name"] = reader.cstring()
			team["type"] = reader.u32()
			team["background"] = reader.u32()
			team["emblem"] = reader.u32()
			team["emblem_color"] = reader.u32()
			team["border"] = reader.u32()
			team["border_color"] = reader.u32()
			changed.emit()
		"SMSG_ARENA_TEAM_STATS":
			var team: Dictionary = _team(reader.u32())
			for key: String in [
				"rating", "games_week", "wins_week", "games_season", "wins_season", "rank",
			]:
				team[key] = reader.u32()
			changed.emit()
		"SMSG_ARENA_TEAM_ROSTER":
			_read_roster(reader)
		"SMSG_ARENA_TEAM_INVITE":
			var inviter: String = reader.cstring()
			invited.emit(inviter, reader.cstring())
		"SMSG_ARENA_TEAM_EVENT":
			var event: int = reader.u8()
			var names: Array = []
			for i: int in reader.u8():
				names.append(reader.cstring())
			if EVENTS.has(event):
				message.emit(_format(EVENTS[event], names))
			changed.emit()
		"SMSG_ARENA_TEAM_COMMAND_RESULT":
			reader.u32()
			var team_name: String = reader.cstring()
			var player_name: String = reader.cstring()
			var error: int = reader.u32()
			if ERRORS.has(error):
				message.emit(_format(ERRORS[error], [team_name, player_name]))


func _read_roster(reader: PacketReader) -> void:
	var team: Dictionary = _team(reader.u32())
	var extended: bool = reader.u8() != 0
	var count: int = reader.u32()
	team["type"] = reader.u32()
	var roster: Array[Dictionary] = []
	for i: int in count:
		var member: Dictionary = {
			"guid": reader.u64(),
			"online": reader.u8() != 0,
			"name": reader.cstring(),
			"captain": reader.u32() == 0,
			"level": reader.u8(),
			"class": reader.u8(),
			"games_week": reader.u32(),
			"wins_week": reader.u32(),
			"games_season": reader.u32(),
			"wins_season": reader.u32(),
			"personal_rating": reader.u32(),
		}
		if extended:
			reader.skip(8)
		roster.append(member)
	team["roster"] = roster
	changed.emit()


# GlobalStrings use %s in order; any the event leaves out stay empty.
static func _format(key: String, names: Array) -> String:
	var text: String = WowStrings.get_text(key)
	for name_text: Variant in names:
		var at: int = text.find("%s")
		if at >= 0:
			text = text.left(at) + str(name_text) + text.substr(at + 2)
	return text.replace("%s", "")
