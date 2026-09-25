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


# An inspected unit shows only its active talent group, so it has no spec tabs.
func _update_specs() -> void:
	pass


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_INSPECT_TALENT":
		return
	var reader: PacketReader = PacketReader.new(payload)
	if reader.packed_guid() != guid:
		return
	var info: Dictionary = Talents.read_groups(reader)
	var groups: Array[Dictionary] = info["groups"]
	_unspent = info["unspent"]
	_ranks.clear()
	if info["active"] < groups.size():
		_ranks.assign(groups[info["active"]]["ranks"])
	refresh()
