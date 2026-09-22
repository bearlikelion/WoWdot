class_name EquipmentSets
extends RefCounted

signal changed

const MAX_SETS: int = 10
const SLOTS: int = 19

# Each set as {guid, index, name, icon, items}, in index order.
var sets: Array[Dictionary] = []

var _session: WowSession


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)


func find(set_name: String) -> Dictionary:
	for entry: Dictionary in sets:
		if entry["name"] == set_name:
			return entry
	return {}


# Saves the worn gear under the name, overwriting the set of that name if there is one.
func save(set_name: String, icon: String) -> void:
	var entry: Dictionary = find(set_name)
	if entry.is_empty():
		var index: int = _free_index()
		if index < 0:
			return
		entry = {"guid": 0, "index": index}
		sets.append(entry)
		sets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["index"] < b["index"])
	var items: Array[int] = []
	for slot: int in SLOTS:
		items.append(Inventory.equipped(slot as Inventory.Slot))
	entry["name"] = set_name
	entry["icon"] = icon
	entry["items"] = items
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	_put_packed_guid(buffer, entry["guid"])
	buffer.put_u32(entry["index"])
	_put_cstring(buffer, set_name)
	_put_cstring(buffer, icon)
	for item: int in items:
		_put_packed_guid(buffer, item)
	_session.send_packet("CMSG_EQUIPMENT_SET_SAVE", buffer.data_array)
	changed.emit()


func use(entry: Dictionary) -> void:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	for item: int in entry["items"]:
		_put_packed_guid(buffer, item)
		# The source bag and slot, which the server only logs.
		buffer.put_u8(0)
		buffer.put_u8(0)
	_session.send_packet("CMSG_EQUIPMENT_SET_USE", buffer.data_array)


func delete(entry: Dictionary) -> void:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	_put_packed_guid(buffer, entry["guid"])
	_session.send_packet("CMSG_DELETEEQUIPMENT_SET", buffer.data_array)
	sets.erase(entry)
	changed.emit()


func _free_index() -> int:
	for index: int in MAX_SETS:
		if sets.all(func(entry: Dictionary) -> bool: return entry["index"] != index):
			return index
	return -1


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_EQUIPMENT_SET_LIST":
			sets.clear()
			for i: int in reader.u32():
				var entry: Dictionary = {
					"guid": reader.packed_guid(),
					"index": reader.u32(),
					"name": reader.cstring(),
					"icon": reader.cstring(),
				}
				var items: Array[int] = []
				for slot: int in SLOTS:
					items.append(reader.packed_guid())
				entry["items"] = items
				sets.append(entry)
			changed.emit()
		"SMSG_EQUIPMENT_SET_SAVED":
			var index: int = reader.u32()
			var guid: int = reader.packed_guid()
			for entry: Dictionary in sets:
				if entry["index"] == index:
					entry["guid"] = guid


static func _put_packed_guid(buffer: StreamPeerBuffer, guid: int) -> void:
	var mask: int = 0
	var bytes: PackedByteArray = []
	for i: int in 8:
		var byte: int = (guid >> (8 * i)) & 0xFF
		if byte:
			mask |= 1 << i
			bytes.append(byte)
	buffer.put_u8(mask)
	buffer.put_data(bytes)


static func _put_cstring(buffer: StreamPeerBuffer, text: String) -> void:
	buffer.put_data(text.to_utf8_buffer())
	buffer.put_u8(0)
