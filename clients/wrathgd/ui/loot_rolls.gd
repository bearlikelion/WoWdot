class_name LootRolls
extends Control

signal message_added(text: String)

const FRAME: PackedScene = preload("res://ui/group_loot_frame.tscn")
const FRAME_GAP: float = 90.0
# A roll number over this means the player passed, as GroupLootFrame reads it.
const PASSED_ROLL: int = 127
const PASSED_LINE: String = "%s passed on: %s"
const ROLLED_LINE: String = "%s rolls %d for: %s"
const WON_LINE: String = "%s won: %s (roll %d)"

var _frames: Dictionary[int, GroupLootFrame] = {}


func _ready() -> void:
	WowClient.session.packet_received.connect(_on_packet_received)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_LOOT_START_ROLL":
			_start_roll(reader)
		"SMSG_LOOT_ROLL":
			_on_roll(reader)
		"SMSG_LOOT_ROLL_WON":
			_on_won(reader)


func _start_roll(reader: PacketReader) -> void:
	var target: int = reader.u64()
	if PacketReader.wotlk:
		reader.u32()
	var slot: int = reader.u32()
	var item_entry: int = reader.u32()
	reader.u32()
	reader.u32()
	if PacketReader.wotlk:
		reader.u32()
	var seconds: float = reader.u32() / 1000.0
	var frame: GroupLootFrame = FRAME.instantiate()
	add_child(frame)
	frame.position.y = _frames.size() * FRAME_GAP
	frame.rolled.connect(_send_roll.bind(target, slot))
	frame.tree_exited.connect(_forget.bind(slot))
	_frames[slot] = frame
	frame.show_roll(item_entry, seconds)


func _forget(slot: int) -> void:
	_frames.erase(slot)


func _send_roll(roll: GroupLootFrame.Roll, target: int, slot: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(13)
	payload.encode_u64(0, target)
	payload.encode_u32(8, slot)
	payload.encode_u8(12, roll)
	WowClient.session.send_packet("CMSG_LOOT_ROLL", payload)


func _on_roll(reader: PacketReader) -> void:
	reader.u64()
	reader.u32()
	var roller: String = WowClient.session.get_object_name(reader.u64())
	var item_entry: int = reader.u32()
	reader.u32()
	reader.u32()
	var number: int = reader.u8()
	if number > PASSED_ROLL:
		message_added.emit(PASSED_LINE % [roller, _link(item_entry)])
		return
	message_added.emit(ROLLED_LINE % [roller, number, _link(item_entry)])


func _on_won(reader: PacketReader) -> void:
	reader.u64()
	reader.u32()
	var item_entry: int = reader.u32()
	reader.u32()
	reader.u32()
	var winner: String = WowClient.session.get_object_name(reader.u64())
	var number: int = reader.u8()
	message_added.emit(WON_LINE % [winner, _link(item_entry), number])


# The stock lines carry an item link with fields we do not track, so these are ours.
func _link(item_entry: int) -> String:
	return "[%s]" % WowClient.session.get_item_info(item_entry).get("name", "")
