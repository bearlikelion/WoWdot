class_name Barbershop
extends RefCounted

signal opened
signal closed
signal preview_changed
signal refused(result: Result)

enum Result { OK, NO_MONEY, NOT_SEATED, NO_MONEY_TOO }
enum StyleType { HAIR, FACIAL_HAIR = 2, SKIN = 3 }

# The look being tried in the chair, over the player's own: hair_style, hair_color, facial_hair.
var preview: Dictionary = {}

var _session: WowSession


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)


func set_preview(look: Dictionary) -> void:
	preview = look
	preview_changed.emit()


# CMSG_ALTER_APPEARANCE names hair and facial hair by BarberShopStyle row, the colour by index.
func apply(hair_style_id: int, hair_color: int, facial_hair_id: int, skin_id: int = 0) -> void:
	var payload: PackedByteArray = []
	payload.resize(16)
	payload.encode_u32(0, hair_style_id)
	payload.encode_u32(4, hair_color)
	payload.encode_u32(8, facial_hair_id)
	payload.encode_u32(12, skin_id)
	_session.send_packet("CMSG_ALTER_APPEARANCE", payload)


# Getting up from the chair, which the stock Cancel button does.
func leave() -> void:
	var payload: PackedByteArray = []
	payload.resize(4)
	_session.send_packet("CMSG_STANDSTATECHANGE", payload)
	_close()


func _close() -> void:
	set_preview({})
	closed.emit()


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	match opcode:
		"SMSG_ENABLE_BARBER_SHOP":
			opened.emit()
		"SMSG_BARBER_SHOP_RESULT":
			var result: Result = PacketReader.new(payload).u32() as Result
			if result == Result.OK:
				_close()
			else:
				refused.emit(result)
