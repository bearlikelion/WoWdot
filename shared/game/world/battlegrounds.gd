class_name Battlegrounds
extends RefCounted

signal listed(map_id: int, instances: PackedInt32Array)
signal queue_changed(slot: int, status: Status, map_id: int)
signal refused(reason: int)
signal world_state_changed(field: int, value: int)

# SMSG_BATTLEFIELD_STATUS's statusId.
enum Status { NONE, WAIT_QUEUE, WAIT_JOIN, IN_PROGRESS, WAIT_LEAVE }
# CMSG_BATTLEFIELD_PORT's action byte.
enum Port { LEAVE, ENTER }

# In 1.12 the wire names a battleground by the map it runs on.
const ALTERAC_VALLEY: int = 30
const WARSONG_GULCH: int = 489
const ARATHI_BASIN: int = 529
# A character stands in at most three queues at once.
const QUEUE_SLOTS: int = 3

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
			reader.u64()
			var map_id: int = reader.u32()
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
			var count: int = reader.u16()
			for i: int in count:
				_set_state(reader.u32(), reader.u32())
		"SMSG_UPDATE_WORLD_STATE":
			_set_state(reader.u32(), reader.u32())


# A cleared slot is the same opcode with a zero map, and carries nothing after it.
func _read_status(reader: PacketReader) -> void:
	var slot: int = reader.u32()
	if slot < 0 or slot >= _queues.size():
		return
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


func _set_state(field: int, value: int) -> void:
	_states[field] = value
	world_state_changed.emit(field, value)
