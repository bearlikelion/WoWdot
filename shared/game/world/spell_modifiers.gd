class_name SpellModifiers
extends RefCounted

signal changed

# SpellModOp, the ones the tooltip shows.
enum Op { DURATION = 1, RANGE = 5, CASTING_TIME = 10, COOLDOWN = 11, COST = 14 }

const BITS: int = 96
# ChrClasses' SpellClassSet by class id: the spell family a class's own spells belong to.
const CLASS_FAMILIES: Dictionary[int, int] = {
	1: 4, 2: 10, 3: 9, 4: 8, 5: 6, 6: 15, 7: 11, 8: 3, 9: 5, 11: 7,
}

# Op to the total for each SpellFamilyFlags bit, as Player::AddSpellMod sends them.
var _flat: Dictionary[int, PackedInt32Array] = {}
var _percent: Dictionary[int, PackedInt32Array] = {}
var _session: WowSession
var _spells: WowDBC


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)
	# The server sends every modifier again when a character enters the world.
	session.state_changed.connect(func(state: int, _message: String) -> void:
		if state == WowSession.STATE_CHARACTER_LIST:
			_flat.clear()
			_percent.clear()
	)


# SpellMgr's ApplySpellMod: the flat total over the spell's family bits, then the percent.
func apply(spell_id: int, op: Op, base: float) -> float:
	if not PacketReader.wotlk or (not _flat.has(op) and not _percent.has(op)):
		return base
	if _spells == null:
		_spells = WowDBC.open(WowAssets.archive, "Spell")
	var row: int = _spells.find(spell_id)
	if row < 0:
		return base
	var guid: int = _session.get_player_guid()
	var class_id: int = (_session.get_field(guid, "UNIT_FIELD_BYTES_0") >> 8) & 0xFF
	if _spells.get_uint(row, "SpellFamilyName") != CLASS_FAMILIES.get(class_id, -1):
		return base
	var flats: PackedInt32Array = _flat.get(op, PackedInt32Array())
	var percents: PackedInt32Array = _percent.get(op, PackedInt32Array())
	var flat: int = 0
	var percent: int = 0
	for word: int in 3:
		var flags: int = _spells.get_uint(row, "SpellFamilyFlags%d" % word)
		for bit: int in 32:
			if flags & (1 << bit):
				flat += flats[word * 32 + bit] if not flats.is_empty() else 0
				percent += percents[word * 32 + bit] if not percents.is_empty() else 0
	return (base + flat) * (1.0 + percent / 100.0)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var table: Dictionary[int, PackedInt32Array]
	match opcode:
		"SMSG_SET_FLAT_SPELL_MODIFIER":
			table = _flat
		"SMSG_SET_PCT_SPELL_MODIFIER":
			table = _percent
		_:
			return
	var reader: PacketReader = PacketReader.new(payload)
	var bit: int = reader.u8()
	var op: int = reader.u8()
	if bit >= BITS:
		return
	if not table.has(op):
		var totals: PackedInt32Array = []
		totals.resize(BITS)
		table[op] = totals
	table[op][bit] = reader.i32()
	changed.emit()
