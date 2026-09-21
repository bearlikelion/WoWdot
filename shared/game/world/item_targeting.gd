class_name ItemTargeting
extends RefCounted

signal changed

# SpellCastTargets flag for a cast aimed at an item, which is then named by its packed guid.
const TARGET_FLAG_ITEM: int = 0x10

var _session: WowSession
var _spell: int = 0
# The wire bag and slot of an item being used on another, or (-1, -1) for a plain spell.
var _used: Vector2i = -Vector2i.ONE


func _init(session: WowSession) -> void:
	_session = session
	session.world_entered.connect(func(_map: int, _at: Vector3, _facing: float) -> void: cancel())


func is_active() -> bool:
	return _spell != 0 or _used.x >= 0


func begin_spell(spell_id: int) -> void:
	_spell = spell_id
	_used = -Vector2i.ONE
	changed.emit()


func begin_item(wire_address: Vector2i) -> void:
	_spell = 0
	_used = wire_address
	changed.emit()


# True when there was a cast waiting to call off.
func cancel() -> bool:
	if not is_active():
		return false
	_spell = 0
	_used = -Vector2i.ONE
	changed.emit()
	return true


func apply(item_guid: int) -> void:
	var payload: PackedByteArray = PackedByteArray()
	if _spell != 0:
		payload.resize(4)
		payload.encode_u32(0, _spell)
		payload.append_array(_item_target(item_guid))
		_session.send_packet("CMSG_CAST_SPELL", payload)
	else:
		# The third byte picks which of the item's spells to cast; the first is the only one in use.
		payload = PackedByteArray([_used.x, _used.y, 0])
		payload.append_array(_item_target(item_guid))
		_session.send_packet("CMSG_USE_ITEM", payload)
	cancel()


# A packed guid is a mask of which bytes are not zero, followed by just those bytes.
func _item_target(item_guid: int) -> PackedByteArray:
	var target: PackedByteArray = PackedByteArray([TARGET_FLAG_ITEM, 0, 0])
	for i: int in 8:
		var byte: int = (item_guid >> (i * 8)) & 0xFF
		if byte != 0:
			target[2] |= 1 << i
			target.append(byte)
	return target
