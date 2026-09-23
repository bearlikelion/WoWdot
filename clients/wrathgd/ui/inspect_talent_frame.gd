class_name InspectTalentFrame
extends TalentFrame

# The unit whose SMSG_INSPECT_TALENT ranks are shown.
var guid: int = 0

# Talent id to the points in it, for the inspected unit's active talent group.
var _ranks: Dictionary[int, int] = {}
var _unspent: int = 0


func _ready() -> void:
	_setup()
	WowClient.session.packet_received.connect(_on_packet_received)


func clear() -> void:
	_ranks.clear()
	_unspent = 0


func _prefix() -> String:
	return "InspectTalentFrame"


func _unit() -> int:
	return guid


func _load_ranks() -> void:
	_points = _unspent


func _rank(row: int) -> int:
	return _ranks.get(_talents.get_uint(row, "ID"), 0)


func _learnable(_row: int) -> bool:
	return false


# Player::BuildPlayerTalentsInfoData after the unit's packed guid; ranks count from 0.
func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_INSPECT_TALENT":
		return
	var reader: PacketReader = PacketReader.new(payload)
	if reader.packed_guid() != guid:
		return
	_unspent = reader.u32()
	var groups: int = reader.u8()
	var active: int = reader.u8()
	_ranks.clear()
	for group: int in groups:
		for i: int in reader.u8():
			var talent: int = reader.u32()
			var rank: int = reader.u8()
			if group == active:
				_ranks[talent] = rank + 1
		reader.skip(reader.u8() * 2)
	refresh()
