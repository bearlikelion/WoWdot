class_name Proficiencies
extends RefCounted

# ItemSubClass.dbc: the pair that keys a row, and the name the tooltip prints.
const CLASS_COLUMN: int = 0
const SUBCLASS_COLUMN: int = 1
const NAME_COLUMN: int = 10
# Only weapons and armour are gated; everything else is usable by anyone.
const GATED_CLASSES: Array[int] = [2, 4]

# SMSG_SET_PROFICIENCY's subclass bitmask, per item class.
var _masks: Dictionary[int, int] = {}
var _names: Dictionary[Vector2i, String] = {}


func _init(session: WowSession) -> void:
	session.packet_received.connect(_on_packet_received)


func can_use(item_class: int, subclass: int) -> bool:
	if item_class not in GATED_CLASSES or not _masks.has(item_class):
		return true
	return (_masks[item_class] & (1 << subclass)) != 0


func subclass_name(item_class: int, subclass: int) -> String:
	if _names.is_empty():
		var table: WowDBC = WowDBC.open(WowAssets.archive, "ItemSubClass")
		for row: int in table.row_count():
			var key: Vector2i = Vector2i(
				table.get_uint(row, CLASS_COLUMN), table.get_uint(row, SUBCLASS_COLUMN),
			)
			_names[key] = table.get_text(row, NAME_COLUMN)
	return _names.get(Vector2i(item_class, subclass), "")


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode == "SMSG_SET_PROFICIENCY" and payload.size() >= 5:
		_masks[payload.decode_u8(0)] = payload.decode_u32(1)
