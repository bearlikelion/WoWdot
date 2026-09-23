class_name BattlefieldManager
extends RefCounted

# Wintergrasp's battlefield manager: world PvP queued and entered from the zone itself.
signal invited_to_queue(warmup: bool)
signal invited_to_enter(seconds_left: int)
signal queued(accepted: bool, has_room: bool, warmup: bool)
signal entered
signal eject_pending
signal ejected

# Wintergrasp, the only battlefield 3.3.5 runs.
const WINTERGRASP: int = 1

var battle_id: int = WINTERGRASP
var in_battle: bool = false

var _session: WowSession


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)


func answer_queue_invite(accept: bool) -> void:
	_send("CMSG_BATTLEFIELD_MGR_QUEUE_INVITE_RESPONSE", accept)


func answer_entry_invite(accept: bool) -> void:
	_send("CMSG_BATTLEFIELD_MGR_ENTRY_INVITE_RESPONSE", accept)


func leave() -> void:
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_u32(0, battle_id)
	_session.send_packet("CMSG_BATTLEFIELD_MGR_EXIT_REQUEST", payload)


func _send(opcode: String, accept: bool) -> void:
	var payload: PackedByteArray = []
	payload.resize(5)
	payload.encode_u32(0, battle_id)
	payload[4] = int(accept)
	_session.send_packet(opcode, payload)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if not opcode.begins_with("SMSG_BATTLEFIELD_MGR_"):
		return
	var reader: PacketReader = PacketReader.new(payload)
	battle_id = reader.u32()
	match opcode:
		"SMSG_BATTLEFIELD_MGR_QUEUE_INVITE":
			invited_to_queue.emit(reader.u8() != 0)
		"SMSG_BATTLEFIELD_MGR_ENTRY_INVITE":
			reader.u32()
			# The deadline is unix time, read against the local clock.
			var deadline: int = reader.u32()
			invited_to_enter.emit(maxi(deadline - int(Time.get_unix_time_from_system()), 0))
		"SMSG_BATTLEFIELD_MGR_QUEUE_REQUEST_RESPONSE":
			reader.u32()
			var accepted: bool = reader.u8() != 0
			var has_room: bool = reader.u8() != 0
			queued.emit(accepted, has_room, reader.u8() != 0)
		"SMSG_BATTLEFIELD_MGR_ENTERED":
			in_battle = true
			entered.emit()
		"SMSG_BATTLEFIELD_MGR_EJECT_PENDING":
			eject_pending.emit()
		"SMSG_BATTLEFIELD_MGR_EJECTED":
			in_battle = false
			ejected.emit()
