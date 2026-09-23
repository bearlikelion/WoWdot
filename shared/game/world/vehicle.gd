class_name Vehicle
extends RefCounted

# The server handed the player a vehicle to drive, or took it back.
signal changed

# The vehicle the player drives, or 0; movement goes out under its guid while set.
var driving: int = 0

var _session: WowSession


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)


func leave() -> void:
	_session.send_packet("CMSG_REQUEST_VEHICLE_EXIT", PackedByteArray())


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_CLIENT_CONTROL_UPDATE" or not PacketReader.wotlk:
		return
	var reader: PacketReader = PacketReader.new(payload)
	var guid: int = reader.packed_guid()
	var allowed: bool = reader.u8() != 0
	var me: int = _session.get_player_guid()
	var now: int = driving
	if guid == me and allowed:
		now = 0
	elif guid != me and allowed:
		now = guid
	if now == driving:
		return
	driving = now
	_session.set_mover(driving if driving else me)
	changed.emit()
