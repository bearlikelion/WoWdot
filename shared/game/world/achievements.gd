class_name Achievements
extends RefCounted

signal changed
signal earned(achievement_id: int)
signal title_earned(title_bit: int, gained: bool)

const LIST_END: int = 0xFFFFFFFF

# Completed achievement ids to their packed completion date.
var completed: Dictionary[int, int] = {}
# Criteria ids to their progress counter.
var criteria: Dictionary[int, int] = {}

var _session: WowSession
var _achievements: WowDBC


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)


# AppendPackedTime's bit fields, as the day, month and year shown under an achievement.
static func unpack_date(packed: int) -> Dictionary:
	return {
		"day": ((packed >> 14) & 0x3F) + 1,
		"month": ((packed >> 20) & 0xF) + 1,
		"year": ((packed >> 24) & 0x1F) + 2000,
	}


func title(id: int) -> String:
	var row: int = _table().find(id)
	return _achievements.get_text(row, "Title") if row >= 0 else ""


func points() -> int:
	var total: int = 0
	for id: int in completed:
		var row: int = _table().find(id)
		if row >= 0:
			total += _achievements.get_uint(row, "Points")
	return total


func set_title(title_bit: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_s32(0, title_bit)
	_session.send_packet("CMSG_SET_TITLE", payload)


func _table() -> WowDBC:
	if _achievements == null:
		_achievements = WowDBC.open(WowAssets.archive, "Achievement")
	return _achievements


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_ALL_ACHIEVEMENT_DATA":
			completed.clear()
			criteria.clear()
			var id: int = reader.u32()
			while id != LIST_END and reader.remaining() > 0:
				completed[id] = reader.u32()
				id = reader.u32()
			id = reader.u32()
			while id != LIST_END and reader.remaining() > 0:
				criteria[id] = reader.packed_guid()
				reader.packed_guid()
				reader.skip(16)
				id = reader.u32()
			changed.emit()
		"SMSG_ACHIEVEMENT_EARNED":
			var guid: int = reader.packed_guid()
			var id: int = reader.u32()
			if guid == _session.get_player_guid():
				completed[id] = reader.u32()
				earned.emit(id)
				changed.emit()
		"SMSG_CRITERIA_UPDATE":
			var id: int = reader.u32()
			criteria[id] = reader.packed_guid()
			changed.emit()
		"SMSG_ACHIEVEMENT_DELETED":
			completed.erase(reader.u32())
			changed.emit()
		"SMSG_CRITERIA_DELETED":
			criteria.erase(reader.u32())
			changed.emit()
		"SMSG_TITLE_EARNED":
			var title_bit: int = reader.u32()
			title_earned.emit(title_bit, reader.u32() != 0)
