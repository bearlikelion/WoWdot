class_name ItemTargeting
extends RefCounted

signal changed

# SpellCastTargets flag for a cast aimed at an item, which is then named by its packed guid.
const TARGET_FLAG_ITEM: int = 0x10
const TARGET_FLAG_GAMEOBJECT: int = 0x800

var _session: WowSession
var _spell: int = 0
# The wire bag and slot of an item being used on another, or (-1, -1) for a plain spell.
var _used: Vector2i = -Vector2i.ONE
# The item being used is a glyph, so it waits for a socket instead of a target.
var _glyph: bool = false


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
	_glyph = false
	changed.emit()


func begin_glyph(wire_address: Vector2i) -> void:
	begin_item(wire_address)
	_glyph = true


func is_glyph() -> bool:
	return _glyph and _used.x >= 0


func place_glyph(socket: int) -> void:
	use_item(_used, targets(0), socket)
	cancel()


# True when there was a cast waiting to call off.
func cancel() -> bool:
	if not is_active():
		return false
	_spell = 0
	_used = -Vector2i.ONE
	_glyph = false
	changed.emit()
	return true


func apply(item_guid: int) -> void:
	var target: PackedByteArray = targets(TARGET_FLAG_ITEM, item_guid)
	if _spell != 0:
		cast(_spell, target)
	else:
		use_item(_used, target)
	cancel()


static func cast(spell_id: int, target: PackedByteArray) -> void:
	var payload: PackedByteArray = PackedByteArray()
	if PacketReader.wotlk:
		payload.append(0)
	payload.resize(payload.size() + 4)
	payload.encode_u32(payload.size() - 4, spell_id)
	if PacketReader.wotlk:
		payload.append(0)
	payload.append_array(target)
	WowClient.session.send_packet("CMSG_CAST_SPELL", payload)


# CMSG_USE_ITEM; 3.3.5 adds a cast count, the item's spell and guid, a glyph slot and cast flags.
static func use_item(
	address: Vector2i, target: PackedByteArray = targets(0), glyph_slot: int = 0,
) -> void:
	var payload: PackedByteArray = PackedByteArray([address.x, address.y, 0])
	if PacketReader.wotlk:
		var item: int = Inventory.item_at(address)
		var spells: PackedInt32Array = WowClient.session.get_item_info(Inventory.entry(item)) \
				.get("use_spells", PackedInt32Array())
		payload.resize(20)
		payload.encode_u32(3, spells[0] if not spells.is_empty() else 0)
		payload.encode_u64(7, item)
		payload.encode_u32(15, glyph_slot)
		payload[19] = 0
	payload.append_array(target)
	WowClient.session.send_packet("CMSG_USE_ITEM", payload)


# SpellCastTargets: a flag mask, four bytes in 3.3.5 and two before, then a packed guid if one is named.
static func targets(mask: int, guid: int = 0) -> PackedByteArray:
	var target: PackedByteArray = PackedByteArray()
	target.resize(4 if PacketReader.wotlk else 2)
	target.encode_u16(0, mask)
	if mask == 0:
		return target
	var guid_mask: int = target.size()
	target.append(0)
	for i: int in 8:
		var byte: int = (guid >> (i * 8)) & 0xFF
		if byte != 0:
			target[guid_mask] |= 1 << i
			target.append(byte)
	return target
