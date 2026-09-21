class_name UnitAuras
extends RefCounted

enum DispelType { NONE, MAGIC, CURSE, DISEASE, POISON }

const SLOTS: int = 48
const FIRST_HARMFUL: int = 32
# DebuffTypeColor from BuffFrame.lua, for harmful aura borders.
const DISPEL_COLORS: Dictionary[DispelType, Color] = {
	DispelType.NONE: Color(0.8, 0.0, 0.0),
	DispelType.MAGIC: Color(0.2, 0.6, 1.0),
	DispelType.CURSE: Color(0.6, 0.0, 1.0),
	DispelType.DISEASE: Color(0.6, 0.4, 0.0),
	DispelType.POISON: Color(0.0, 0.6, 0.0),
}


# Each aura the unit shows as slot, spell and stack count; slots 32 and up are harmful.
# 3.3.5 dropped the aura fields for SMSG_AURA_UPDATE, which the session tracks per unit instead.
static func read(session: WowSession, guid: int) -> Array[Dictionary]:
	var first: int = session.field_index("UNIT_FIELD_AURAS")
	if first < 0:
		var tracked: Array[Dictionary] = []
		tracked.assign(session.get_auras(guid))
		return tracked
	var applications: int = session.field_index("UNIT_FIELD_AURAAPPLICATIONS")
	var auras: Array[Dictionary] = []
	for slot: int in SLOTS:
		var spell: int = session.get_field(guid, first + slot)
		if spell == 0:
			continue
		# One byte per slot holding the stack count minus one.
		var packed: int = session.get_field(guid, applications + (slot >> 2))
		var stacks: int = ((packed >> ((slot & 3) * 8)) & 0xFF) + 1
		auras.append({"slot": slot, "spell": spell, "stacks": stacks, "harmful": slot >= FIRST_HARMFUL})
	return auras


static func border_color(spell_id: int) -> Color:
	var dispel: DispelType = WowAssets.spells.dispel_type(spell_id) as DispelType
	return DISPEL_COLORS.get(dispel, DISPEL_COLORS[DispelType.NONE])
