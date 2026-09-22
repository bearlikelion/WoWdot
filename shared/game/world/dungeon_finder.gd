class_name DungeonFinder
extends RefCounted

signal changed
signal role_check_started
signal proposal_updated
signal rewarded(reward: Dictionary)
signal failed(text: String)

enum State { NONE, ROLE_CHECK, QUEUED, PROPOSAL, DUNGEON }
enum Role { LEADER = 0x1, TANK = 0x2, HEALER = 0x4, DAMAGE = 0x8 }
enum ProposalState { INITIATING, FAILED, SUCCESS }
# LfgUpdateType, the reason an SMSG_LFG_UPDATE_PLAYER or _PARTY was sent.
enum Update {
	LEAVE = 1, ROLE_CHECK_ABORTED = 4, JOIN_QUEUE = 5, ROLE_CHECK_FAILED = 6,
	REMOVED_FROM_QUEUE = 7, PROPOSAL_FAILED = 8, PROPOSAL_DECLINED = 9, GROUP_FOUND = 10,
	ADDED_TO_QUEUE = 12, PROPOSAL_BEGIN = 13, UPDATE_STATUS = 14, MEMBER_OFFLINE = 15,
	DISBAND = 16,
}

const ENTRY_ID_MASK: int = 0xFFFFFF
# GetAvailableRoles: the classes that can tank and heal, by class id.
const TANK_CLASSES: Array[int] = [1, 2, 6, 11]
const HEALER_CLASSES: Array[int] = [2, 5, 7, 11]
# LfgJoinResult codes and the GlobalStrings they show as.
const JOIN_ERRORS: Dictionary[int, String] = {
	1: "ERR_LFG_ROLE_CHECK_FAILED",
	2: "ERR_LFG_GROUP_FULL",
	4: "ERR_LFG_NO_LFG_OBJECT",
	5: "ERR_LFG_NO_SLOTS_PLAYER",
	6: "ERR_LFG_NO_SLOTS_PARTY",
	7: "ERR_LFG_MISMATCHED_SLOTS",
	8: "ERR_LFG_PARTY_PLAYERS_FROM_DIFFERENT_REALMS",
	9: "ERR_LFG_MEMBERS_NOT_PRESENT",
	10: "ERR_LFG_GET_INFO_TIMEOUT",
	11: "ERR_LFG_INVALID_SLOT",
	12: "ERR_LFG_DESERTER_PLAYER",
	13: "ERR_LFG_DESERTER_PARTY",
	14: "ERR_LFG_RANDOM_COOLDOWN_PLAYER",
	15: "ERR_LFG_RANDOM_COOLDOWN_PARTY",
	16: "ERR_LFG_TOO_MANY_MEMBERS",
	17: "ERR_LFG_CANT_USE_DUNGEONS",
}

var state: State = State.NONE
# The random dungeons offered, each {entry, done, money, xp, items}.
var random_dungeons: Array[Dictionary] = []
# Dungeon entries the player cannot queue for, to the LfgLockStatusType why.
var locks: Dictionary[int, int] = {}
var queued_dungeons: Array[int] = []
# The latest SMSG_LFG_QUEUE_STATUS: dungeon, wait times in seconds and the roles still needed.
var queue_status: Dictionary = {}
# The latest SMSG_LFG_PROPOSAL_UPDATE; each of its players is {role, self, answered, accepted}.
var proposal: Dictionary = {}
var role_check_dungeons: Array[int] = []

var _session: WowSession
var _dungeons: WowDBC


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)


static func dungeon_id(entry: int) -> int:
	return entry & ENTRY_ID_MASK


# The roles the player's class can take, leader included.
func available_roles() -> int:
	var bytes: int = _session.get_field(_session.get_player_guid(), "UNIT_FIELD_BYTES_0")
	var class_id: int = (bytes >> 8) & 0xFF
	var roles: int = Role.LEADER | Role.DAMAGE
	if class_id in TANK_CLASSES:
		roles |= Role.TANK
	if class_id in HEALER_CLASSES:
		roles |= Role.HEALER
	return roles


func dungeon_name(entry: int) -> String:
	if _dungeons == null:
		_dungeons = WowDBC.open(WowAssets.archive, "LFGDungeons")
	var row: int = _dungeons.find(dungeon_id(entry))
	return _dungeons.get_string(row, "Name") if row >= 0 else ""


func request_info() -> void:
	_session.send_packet("CMSG_LFD_PLAYER_LOCK_INFO_REQUEST", PackedByteArray())


func join(roles: int, entries: Array[int]) -> void:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u32(roles)
	# No partial clear and no achievements wanted.
	buffer.put_u8(0)
	buffer.put_u8(0)
	buffer.put_u8(entries.size())
	for entry: int in entries:
		buffer.put_u32(entry)
	# The needs block the client always sends three of.
	buffer.put_u8(3)
	buffer.put_data(PackedByteArray([0, 0, 0]))
	buffer.put_u8(0)
	_session.send_packet("CMSG_LFG_JOIN", buffer.data_array)


func leave() -> void:
	_session.send_packet("CMSG_LFG_LEAVE", PackedByteArray())


func set_roles(roles: int) -> void:
	_session.send_packet("CMSG_LFG_SET_ROLES", PackedByteArray([roles]))


func answer_proposal(accept: bool) -> void:
	var payload: PackedByteArray = []
	payload.resize(5)
	payload.encode_u32(0, proposal.get("id", 0))
	payload[4] = int(accept)
	_session.send_packet("CMSG_LFG_PROPOSAL_RESULT", payload)


func teleport(out: bool) -> void:
	_session.send_packet("CMSG_LFG_TELEPORT", PackedByteArray([int(out)]))


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_LFG_PLAYER_INFO":
			_read_player_info(reader)
		"SMSG_LFG_JOIN_RESULT":
			var result: int = reader.u32()
			if result != 0:
				failed.emit(WowStrings.get_text(JOIN_ERRORS.get(result, "ERR_LFG_NO_LFG_OBJECT")))
		"SMSG_LFG_UPDATE_PLAYER", "SMSG_LFG_UPDATE_PARTY":
			_read_update(reader, opcode == "SMSG_LFG_UPDATE_PARTY")
		"SMSG_LFG_QUEUE_STATUS":
			queue_status = {
				"dungeon": reader.u32(),
				"average_wait": reader.i32(),
				"wait": reader.i32(),
				"tank_wait": reader.i32(),
				"healer_wait": reader.i32(),
				"damage_wait": reader.i32(),
				"tanks_needed": reader.u8(),
				"healers_needed": reader.u8(),
				"damage_needed": reader.u8(),
				"queued_time": reader.u32(),
			}
			changed.emit()
		"SMSG_LFG_ROLE_CHECK_UPDATE":
			var check_state: int = reader.u32()
			var starting: bool = reader.u8() != 0
			role_check_dungeons.clear()
			for i: int in reader.u8():
				role_check_dungeons.append(reader.u32())
			if starting:
				state = State.ROLE_CHECK
				role_check_started.emit()
			elif check_state != 0 and state == State.ROLE_CHECK:
				state = State.NONE
			changed.emit()
		"SMSG_LFG_PROPOSAL_UPDATE":
			_read_proposal(reader)
		"SMSG_LFG_PLAYER_REWARD":
			var reward: Dictionary = {
				"random_dungeon": reader.u32(),
				"dungeon": reader.u32(),
				"done": reader.u8() != 0,
			}
			reader.skip(4)
			reward["money"] = reader.u32()
			reward["xp"] = reader.u32()
			state = State.DUNGEON
			rewarded.emit(reward)
		"SMSG_LFG_TELEPORT_DENIED":
			failed.emit(WowStrings.get_text("ERR_LFG_NO_LFG_OBJECT"))
		"SMSG_LFG_DISABLED":
			failed.emit(WowStrings.get_text("ERR_LFG_CANT_USE_DUNGEONS"))


func _read_player_info(reader: PacketReader) -> void:
	random_dungeons.clear()
	for i: int in reader.u8():
		var dungeon: Dictionary = {
			"entry": reader.u32(),
			"done": reader.u8() != 0,
			"money": reader.u32(),
			"xp": reader.u32(),
		}
		reader.skip(8)
		var items: Array[Dictionary] = []
		for j: int in reader.u8():
			items.append({"item": reader.u32(), "display": reader.u32(), "count": reader.u32()})
		dungeon["items"] = items
		random_dungeons.append(dungeon)
	locks.clear()
	for i: int in reader.u32():
		var entry: int = reader.u32()
		locks[entry] = reader.u32()
	changed.emit()


func _read_update(reader: PacketReader, party: bool) -> void:
	var update: int = reader.u8()
	if reader.u8() != 0:
		if party:
			reader.skip(1)
		var queued: bool = reader.u8() != 0
		reader.skip(2)
		if party:
			reader.skip(3)
		queued_dungeons.clear()
		for i: int in reader.u8():
			queued_dungeons.append(reader.u32())
		if queued:
			state = State.QUEUED
	match update:
		Update.JOIN_QUEUE, Update.ADDED_TO_QUEUE:
			state = State.QUEUED
		Update.PROPOSAL_BEGIN:
			state = State.PROPOSAL
		Update.GROUP_FOUND:
			state = State.DUNGEON
		Update.LEAVE, Update.ROLE_CHECK_ABORTED, Update.ROLE_CHECK_FAILED, \
		Update.REMOVED_FROM_QUEUE, Update.PROPOSAL_FAILED, Update.PROPOSAL_DECLINED:
			state = State.NONE
			queue_status.clear()
	changed.emit()


func _read_proposal(reader: PacketReader) -> void:
	proposal = {
		"dungeon": reader.u32(),
		"state": reader.u8(),
		"id": reader.u32(),
		"encounters": reader.u32(),
		"silent": reader.u8() != 0,
	}
	var players: Array[Dictionary] = []
	for i: int in reader.u8():
		var player: Dictionary = {"role": reader.u32(), "self": reader.u8() != 0}
		reader.skip(2)
		player["answered"] = reader.u8() != 0
		player["accepted"] = reader.u8() != 0
		players.append(player)
	proposal["players"] = players
	if proposal["state"] == ProposalState.INITIATING:
		state = State.PROPOSAL
	proposal_updated.emit()
	changed.emit()
