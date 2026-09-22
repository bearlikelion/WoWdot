class_name Battlegrounds
extends RefCounted

signal listed(map_id: int, instances: PackedInt32Array)
signal queue_changed(slot: int, status: Status, map_id: int)
signal refused(reason: int)
signal world_state_changed(field: int, value: int)
signal scores_changed
signal positions_changed

# MSG_PVP_LOG_DATA's winner byte once the battle has ended.
enum Winner { HORDE, ALLIANCE, NONE }
# SMSG_BATTLEFIELD_STATUS's statusId.
enum Status { NONE, WAIT_QUEUE, WAIT_JOIN, IN_PROGRESS, WAIT_LEAVE }
# CMSG_BATTLEFIELD_PORT's action byte.
enum Port { LEAVE, ENTER }

# In 1.12 the wire names a battleground by the map it runs on.
# 3.3.5 names a battleground by its BattlemasterList id where 1.12 named its map.
const BATTLEGROUND_MAPS: Dictionary[int, int] = {1: 30, 2: 489, 3: 529, 7: 566, 9: 607, 30: 628}
const ALTERAC_VALLEY: int = 30
const WARSONG_GULCH: int = 489
const ARATHI_BASIN: int = 529
# A character stands in at most three queues at once.
const QUEUE_SLOTS: int = 3

## One row per player; "stats" holds the battleground's own columns.
var scores: Array[Dictionary] = []
var winner: Winner = Winner.NONE
## Team mates by guid, in WoW map yards, and the flag carrier when the server names one.
var positions: Dictionary[int, Vector2] = {}
var flag_carrier: int = 0
## The battlemaster whose list arrived last, which a join has to name.
var battlemaster: int = 0

var _session: WowSession
var _queues: Array[Dictionary] = []
var _states: Dictionary[int, int] = {}


func _init(session: WowSession) -> void:
	_session = session
	_queues.resize(QUEUE_SLOTS)
	_queues.fill({})
	session.packet_received.connect(_on_packet_received)


# Asks a battlemaster which instances of its battleground are running.
func ask(battlemaster_guid: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, battlemaster_guid)
	_session.send_packet("CMSG_BATTLEMASTER_HELLO", payload)


# An instance of 0 takes the first one with room, which is what the stock window sends.
func join(battlemaster_guid: int, map_id: int, instance_id: int = 0, as_group: bool = false) -> void:
	var payload: PackedByteArray = []
	payload.resize(17)
	payload.encode_u64(0, battlemaster_guid)
	payload.encode_u32(8, map_id)
	payload.encode_u32(12, instance_id)
	payload.encode_u8(16, int(as_group))
	_session.send_packet("CMSG_BATTLEMASTER_JOIN", payload)


func enter(map_id: int) -> void:
	_port(map_id, Port.ENTER)


## Gives up a place in the queue, which is not the same as leaving a battle already joined.
func abandon(map_id: int) -> void:
	_port(map_id, Port.LEAVE)


func leave(map_id: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_u32(0, map_id)
	_session.send_packet("CMSG_LEAVE_BATTLEFIELD", payload)


# What a queue slot holds: "status", "map_id", "instance_id", "time_one", "time_two".
func queue(slot: int) -> Dictionary:
	return _queues[slot] if slot >= 0 and slot < _queues.size() else {}


# The slot this battleground sits in, or -1 when the character is not queued for it.
func slot_of(map_id: int) -> int:
	for slot: int in _queues.size():
		if _queues[slot].get("map_id", 0) == map_id:
			return slot
	return -1


func in_battle() -> bool:
	return _queues.any(func(entry: Dictionary) -> bool:
		return entry.get("status", Status.NONE) == Status.IN_PROGRESS
	)


func request_scores() -> void:
	_session.send_packet("MSG_PVP_LOG_DATA", PackedByteArray())


func request_positions() -> void:
	_session.send_packet("MSG_BATTLEGROUND_PLAYER_POSITIONS", PackedByteArray())


func world_state(field: int) -> int:
	return _states.get(field, 0)


func _port(map_id: int, action: Port) -> void:
	var payload: PackedByteArray = []
	payload.resize(5)
	payload.encode_u32(0, map_id)
	payload.encode_u8(4, action)
	_session.send_packet("CMSG_BATTLEFIELD_PORT", payload)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_BATTLEFIELD_LIST":
			battlemaster = reader.u64()
			var map_id: int = 0
			if PacketReader.wotlk:
				reader.u8()
				map_id = BATTLEGROUND_MAPS.get(reader.u32(), 0)
				reader.skip(15)
				if reader.u8() != 0:
					reader.skip(13)
			else:
				map_id = reader.u32()
				reader.u8()
			var instances: PackedInt32Array = []
			for i: int in reader.u32():
				instances.append(reader.u32())
			listed.emit(map_id, instances)
		"SMSG_BATTLEFIELD_STATUS":
			_read_status(reader)
		"SMSG_GROUP_JOINED_BATTLEGROUND":
			refused.emit(reader.u32())
		"SMSG_INIT_WORLD_STATES":
			reader.u32()
			reader.u32()
			if PacketReader.wotlk:
				reader.u32()
			var count: int = reader.u16()
			for i: int in count:
				_set_state(reader.u32(), reader.u32())
		"MSG_PVP_LOG_DATA":
			_read_scores(reader)
		"MSG_BATTLEGROUND_PLAYER_POSITIONS":
			_read_positions(reader)
		"SMSG_UPDATE_WORLD_STATE":
			_set_state(reader.u32(), reader.u32())


# A cleared slot is the same opcode with a zero map, and carries nothing after it.
func _read_status(reader: PacketReader) -> void:
	var slot: int = reader.u32()
	if slot < 0 or slot >= _queues.size():
		return
	if PacketReader.wotlk:
		return _read_status_wotlk(reader, slot)
	var map_id: int = reader.u32()
	if map_id == 0:
		_queues[slot] = {}
		queue_changed.emit(slot, Status.NONE, 0)
		return
	reader.u8()
	var instance_id: int = reader.u32()
	var status: Status = reader.u32() as Status
	var entry: Dictionary = {
		"status": status, "map_id": map_id, "instance_id": instance_id,
		"time_one": reader.u32(), "time_two": 0,
	}
	# Only these two states write the second time, so reading it otherwise runs off the end.
	if status == Status.WAIT_QUEUE or status == Status.IN_PROGRESS:
		entry["time_two"] = reader.u32()
	_queues[slot] = entry
	queue_changed.emit(slot, status, map_id)


# 3.3.5 packs the arena type, the battleground type and a marker into the eight bytes a zero clears.
func _read_status_wotlk(reader: PacketReader, slot: int) -> void:
	var kind: int = reader.u64()
	if kind == 0:
		_queues[slot] = {}
		queue_changed.emit(slot, Status.NONE, 0)
		return
	var map_id: int = BATTLEGROUND_MAPS.get((kind >> 16) & 0xFFFFFFFF, 0)
	reader.u16()
	var instance_id: int = reader.u32()
	reader.u8()
	var status: Status = reader.u32() as Status
	var entry: Dictionary = {
		"status": status, "map_id": map_id, "instance_id": instance_id,
		"time_one": 0, "time_two": 0,
	}
	if status == Status.WAIT_QUEUE:
		entry["time_one"] = reader.u32()
		entry["time_two"] = reader.u32()
	elif status == Status.WAIT_JOIN or status == Status.IN_PROGRESS:
		entry["map_id"] = reader.u32()
		reader.u64()
		entry["time_one"] = reader.u32()
		if status == Status.IN_PROGRESS:
			entry["time_two"] = reader.u32()
	_queues[slot] = entry
	queue_changed.emit(slot, status, entry["map_id"])


func _read_scores(reader: PacketReader) -> void:
	if PacketReader.wotlk and reader.u8() != 0:
		# Arena scoreboards carry rating and team blocks this frame does not show.
		return
	var ended: bool = reader.u8() != 0
	winner = (reader.u8() as Winner) if ended else Winner.NONE
	scores.clear()
	for i: int in reader.u32():
		var row: Dictionary = {
			"guid": reader.u64(), "rank": 0 if PacketReader.wotlk else reader.u32(),
			"killing_blows": reader.u32(), "honorable_kills": reader.u32(), "deaths": reader.u32(),
			"honor": reader.u32(),
		}
		if PacketReader.wotlk:
			reader.u32()
			reader.u32()
		var stats: PackedInt32Array = []
		for stat: int in reader.u32():
			stats.append(reader.u32())
		row["stats"] = stats
		scores.append(row)
	scores_changed.emit()


func _read_positions(reader: PacketReader) -> void:
	positions.clear()
	for i: int in reader.u32():
		var guid: int = reader.u64()
		positions[guid] = Vector2(reader.f32(), reader.f32())
	flag_carrier = 0
	if PacketReader.wotlk:
		for i: int in reader.u32():
			flag_carrier = reader.u64()
			positions[flag_carrier] = Vector2(reader.f32(), reader.f32())
	elif reader.u8() != 0:
		flag_carrier = reader.u64()
		positions[flag_carrier] = Vector2(reader.f32(), reader.f32())
	positions_changed.emit()


func _set_state(field: int, value: int) -> void:
	_states[field] = value
	world_state_changed.emit(field, value)
