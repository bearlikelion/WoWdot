class_name Duel
extends RefCounted

signal challenged(challenger_name: String)
signal counted_down(seconds: int)
signal finished(text: String)
signal ended

# The Duel spell a challenge is cast as, which plants the flag both players fight over.
const DUEL_SPELL: int = 7266

var _flag: int = 0

var _session: WowSession


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)


func challenge(guid: int) -> void:
	_session.cast_spell(DUEL_SPELL, guid)


func accept() -> void:
	_answer("CMSG_DUEL_ACCEPTED")


func decline() -> void:
	_answer("CMSG_DUEL_CANCELLED")


func _answer(opcode: String) -> void:
	if _flag == 0:
		return
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, _flag)
	_session.send_packet(opcode, payload)
	_flag = 0


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_DUEL_REQUESTED":
			_flag = reader.u64()
			var challenger: int = reader.u64()
			if challenger != _session.get_player_guid():
				challenged.emit(_session.get_object_name(challenger))
		"SMSG_DUEL_COUNTDOWN":
			counted_down.emit(reader.u32())
		"SMSG_DUEL_COMPLETE":
			_flag = 0
			ended.emit()
		"SMSG_DUEL_WINNER":
			var fled: bool = reader.u8() != 0
			var winner: String = reader.cstring()
			var loser: String = reader.cstring()
			var key: String = "DUEL_WINNER_RETREAT" if fled else "DUEL_WINNER_KNOCKOUT"
			finished.emit(WowStrings.get_text(key, "%s has defeated %s in a duel.") % [
				winner, loser,
			])
