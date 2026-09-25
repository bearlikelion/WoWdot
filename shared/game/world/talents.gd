class_name Talents
extends RefCounted

signal changed

# Each talent group as {"ranks": talent id to points, "glyphs": GlyphProperties ids by socket}.
var groups: Array[Dictionary] = []
var active_group: int = 0
var unspent: int = 0
# The pet's talent id to points, and its unspent points, while it has a talent tree.
var pet_ranks: Dictionary[int, int] = {}
var pet_unspent: int = 0
var has_pet_talents: bool = false

var _session: WowSession


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)


# Player::BuildPlayerTalentsInfoData, which SMSG_INSPECT_TALENT also carries after its guid.
static func read_groups(reader: PacketReader) -> Dictionary:
	var unspent_points: int = reader.u32()
	var count: int = reader.u8()
	var active: int = reader.u8()
	var read: Array[Dictionary] = []
	for group: int in count:
		var ranks: Dictionary[int, int] = _read_ranks(reader)
		var glyphs: PackedInt32Array = []
		for glyph: int in reader.u8():
			glyphs.append(reader.u16())
		read.append({"ranks": ranks, "glyphs": glyphs})
	return {"unspent": unspent_points, "active": active, "groups": read}


# Ranks come off the wire counted from 0.
static func _read_ranks(reader: PacketReader) -> Dictionary[int, int]:
	var ranks: Dictionary[int, int] = {}
	for i: int in reader.u8():
		var talent: int = reader.u32()
		ranks[talent] = reader.u8() + 1
	return ranks


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_TALENTS_INFO":
		return
	var reader: PacketReader = PacketReader.new(payload)
	if reader.u8():
		pet_unspent = reader.u32()
		pet_ranks = _read_ranks(reader)
		has_pet_talents = true
	else:
		var info: Dictionary = read_groups(reader)
		unspent = info["unspent"]
		active_group = info["active"]
		groups.assign(info["groups"])
	changed.emit()
