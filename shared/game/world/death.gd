class_name Death
extends RefCounted

signal corpse_located(wow_position: Vector3, map_id: int)
signal resurrect_offered(caster_name: String, sickness: bool)
signal spirit_healer_offered(healer_guid: int)

# CORPSE_RECLAIM_RADIUS in vMaNGOS, in yards.
const RECLAIM_RANGE: float = 39.0
const CORPSE_TYPE: int = 7
const QUERY_INTERVAL_MSEC: int = 2000

var corpse_map: int = -1
var corpse_position: Vector3 = Vector3.ZERO

var _session: WowSession
var _resurrector: int = 0
var _reclaim_at_msec: int = 0
var _query_at_msec: int = 0


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)


func release() -> void:
	_session.send_packet("CMSG_REPOP_REQUEST", PackedByteArray())


# The corpse may not exist yet when the spirit is released, so this is asked again until it does.
func query_corpse() -> void:
	if Time.get_ticks_msec() < _query_at_msec:
		return
	_query_at_msec = Time.get_ticks_msec() + QUERY_INTERVAL_MSEC
	_session.send_packet("MSG_CORPSE_QUERY", PackedByteArray())


# False while the corpse object itself is out of range, which is when its guid arrives.
func reclaim() -> bool:
	var guid: int = corpse_guid()
	if guid == 0:
		return false
	_session.send_packet("CMSG_RECLAIM_CORPSE", _guid_payload(guid))
	return true


func answer_resurrect(accept: bool) -> void:
	var payload: PackedByteArray = _guid_payload(_resurrector)
	payload.append(1 if accept else 0)
	_session.send_packet("CMSG_RESURRECT_RESPONSE", payload)
	_resurrector = 0


func activate_spirit_healer(healer_guid: int) -> void:
	_session.send_packet("CMSG_SPIRIT_HEALER_ACTIVATE", _guid_payload(healer_guid))


func corpse_guid() -> int:
	var me: int = _session.get_player_guid()
	for guid: int in _session.get_object_guids():
		if _session.get_object_type(guid) == CORPSE_TYPE \
		and _session.get_field(guid, "CORPSE_FIELD_OWNER") == (me & 0xFFFFFFFF):
			return guid
	return 0


func may_reclaim() -> bool:
	return reclaim_wait_msec() == 0


func reclaim_wait_msec() -> int:
	return maxi(_reclaim_at_msec - Time.get_ticks_msec(), 0)


func forget_corpse() -> void:
	corpse_map = -1
	corpse_position = Vector3.ZERO


func _guid_payload(guid: int) -> PackedByteArray:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, guid)
	return payload


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"MSG_CORPSE_QUERY":
			if reader.u8() == 0:
				return forget_corpse()
			# The first map is the dungeon's entrance for a corpse inside an instance.
			reader.u32()
			corpse_position = Vector3(reader.f32(), reader.f32(), reader.f32())
			corpse_map = reader.u32()
			corpse_located.emit(corpse_position, corpse_map)
		"SMSG_CORPSE_RECLAIM_DELAY":
			_reclaim_at_msec = Time.get_ticks_msec() + reader.u32()
		"SMSG_RESURRECT_REQUEST":
			_resurrector = reader.u64()
			var caster: String = reader.text(reader.u32())
			resurrect_offered.emit(caster, reader.u8() != 0)
		"SMSG_SPIRIT_HEALER_CONFIRM":
			spirit_healer_offered.emit(reader.u64())
