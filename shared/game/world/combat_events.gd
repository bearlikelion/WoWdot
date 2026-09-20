class_name CombatEvents
extends RefCounted

signal logged(event: CombatEvent)

enum Kind {
	MELEE, SPELL, PERIODIC, HEAL, PERIODIC_HEAL, ENERGIZE, PERIODIC_ENERGIZE, DAMAGE_SHIELD,
	ENVIRONMENT, KILL, XP,
}
# How an attack or spell landed, as UNIT_COMBAT and the combat log name it.
enum Outcome { HIT, MISS, DODGE, PARRY, BLOCK, EVADE, IMMUNE, DEFLECT, RESIST, ABSORB, REFLECT }
enum AuraType {
	PERIODIC_DAMAGE = 3, PERIODIC_HEAL = 8, OBS_MOD_HEALTH = 20, OBS_MOD_MANA = 21,
	PERIODIC_ENERGIZE = 24, PERIODIC_MANA_LEECH = 64, PERIODIC_DAMAGE_PERCENT = 89,
}

const HIT_MISS: int = 0x10
const HIT_CRITICAL: int = 0x80
const HIT_GLANCING: int = 0x4000
const HIT_CRUSHING: int = 0x8000
const SPELL_CRITICAL: int = 0x02
const VICTIM_OUTCOMES: Dictionary[int, Outcome] = {
	2: Outcome.DODGE, 3: Outcome.PARRY, 5: Outcome.BLOCK, 6: Outcome.EVADE,
	7: Outcome.IMMUNE, 8: Outcome.DEFLECT,
}
const MISS_OUTCOMES: Dictionary[int, Outcome] = {
	1: Outcome.MISS, 2: Outcome.RESIST, 3: Outcome.DODGE, 4: Outcome.PARRY, 5: Outcome.BLOCK,
	6: Outcome.EVADE, 7: Outcome.IMMUNE, 8: Outcome.IMMUNE, 9: Outcome.DEFLECT,
	10: Outcome.ABSORB, 11: Outcome.REFLECT,
}


func _init(session: WowSession) -> void:
	session.packet_received.connect(_on_packet_received)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_ATTACKERSTATEUPDATE":
			_read_melee(reader)
		"SMSG_SPELLNONMELEEDAMAGELOG":
			_read_spell_damage(reader)
		"SMSG_PERIODICAURALOG":
			_read_periodic(reader)
		"SMSG_SPELLHEALLOG":
			_read_heal(reader)
		"SMSG_SPELLENERGIZELOG":
			_read_energize(reader)
		"SMSG_SPELLLOGMISS":
			_read_spell_miss(reader)
		"SMSG_PROCRESIST":
			_read_spell_refusal(reader, Outcome.RESIST)
		"SMSG_SPELLORDAMAGE_IMMUNE":
			_read_spell_refusal(reader, Outcome.IMMUNE)
		"SMSG_SPELLDAMAGESHIELD":
			_read_damage_shield(reader)
		"SMSG_ENVIRONMENTALDAMAGELOG":
			_read_environment(reader)
		"SMSG_PARTYKILLLOG":
			var kill: CombatEvent = CombatEvent.new(Kind.KILL)
			kill.source = reader.u64()
			kill.target = reader.u64()
			logged.emit(kill)
		"SMSG_LOG_XPGAIN":
			var xp: CombatEvent = CombatEvent.new(Kind.XP)
			xp.target = reader.u64()
			xp.amount = reader.u32()
			logged.emit(xp)


func _read_melee(reader: PacketReader) -> void:
	var hit_info: int = reader.u32()
	var event: CombatEvent = CombatEvent.new(Kind.MELEE)
	event.source = reader.packed_guid()
	event.target = reader.packed_guid()
	event.amount = reader.i32()
	for i: int in reader.u8():
		var school: int = reader.i32()
		if i == 0:
			event.school = school
		reader.skip(8)
		event.absorbed += reader.i32()
		event.resisted += reader.i32()
	var victim_state: int = reader.u32()
	reader.skip(4)
	var melee_spell: int = reader.u32()
	event.blocked = reader.i32()
	if melee_spell != 0:
		event.kind = Kind.SPELL
		event.spell = melee_spell
	event.critical = (hit_info & HIT_CRITICAL) != 0
	event.glancing = (hit_info & HIT_GLANCING) != 0
	event.crushing = (hit_info & HIT_CRUSHING) != 0
	if hit_info & HIT_MISS:
		event.outcome = Outcome.MISS
	else:
		event.outcome = VICTIM_OUTCOMES.get(victim_state, _damage_outcome(event))
	logged.emit(event)


func _read_spell_damage(reader: PacketReader) -> void:
	var event: CombatEvent = CombatEvent.new(Kind.SPELL)
	event.target = reader.packed_guid()
	event.source = reader.packed_guid()
	event.spell = reader.u32()
	event.amount = reader.u32()
	event.school = reader.u8()
	event.absorbed = reader.u32()
	event.resisted = reader.i32()
	reader.skip(2)
	event.blocked = reader.u32()
	event.critical = (reader.u32() & SPELL_CRITICAL) != 0
	event.outcome = _damage_outcome(event)
	logged.emit(event)


func _read_periodic(reader: PacketReader) -> void:
	var target: int = reader.packed_guid()
	var source: int = reader.packed_guid()
	var spell: int = reader.u32()
	for i: int in reader.u32():
		var event: CombatEvent = CombatEvent.new(Kind.PERIODIC)
		event.target = target
		event.source = source
		event.spell = spell
		match reader.u32():
			AuraType.PERIODIC_DAMAGE, AuraType.PERIODIC_DAMAGE_PERCENT:
				event.amount = reader.u32()
				event.school = reader.u32()
				event.absorbed = reader.u32()
				event.resisted = reader.i32()
				event.outcome = _damage_outcome(event)
			AuraType.PERIODIC_HEAL, AuraType.OBS_MOD_HEALTH:
				event.kind = Kind.PERIODIC_HEAL
				event.amount = reader.u32()
			AuraType.OBS_MOD_MANA, AuraType.PERIODIC_ENERGIZE:
				event.kind = Kind.PERIODIC_ENERGIZE
				event.power = reader.u32()
				event.amount = reader.u32()
			AuraType.PERIODIC_MANA_LEECH:
				reader.skip(12)
				continue
			_:
				return
		logged.emit(event)


func _read_heal(reader: PacketReader) -> void:
	var event: CombatEvent = CombatEvent.new(Kind.HEAL)
	event.target = reader.packed_guid()
	event.source = reader.packed_guid()
	event.spell = reader.u32()
	event.amount = reader.u32()
	event.critical = reader.u8() != 0
	logged.emit(event)


func _read_energize(reader: PacketReader) -> void:
	var event: CombatEvent = CombatEvent.new(Kind.ENERGIZE)
	event.target = reader.packed_guid()
	event.source = reader.packed_guid()
	event.spell = reader.u32()
	event.power = reader.u32()
	event.amount = reader.u32()
	logged.emit(event)


func _read_spell_miss(reader: PacketReader) -> void:
	var spell: int = reader.u32()
	var source: int = reader.u64()
	reader.skip(1)
	for i: int in reader.u32():
		var event: CombatEvent = CombatEvent.new(Kind.SPELL)
		event.source = source
		event.spell = spell
		event.target = reader.u64()
		event.outcome = MISS_OUTCOMES.get(reader.u8(), Outcome.MISS)
		logged.emit(event)


func _read_spell_refusal(reader: PacketReader, outcome: Outcome) -> void:
	var event: CombatEvent = CombatEvent.new(Kind.SPELL)
	event.source = reader.u64()
	event.target = reader.u64()
	event.spell = reader.u32()
	event.outcome = outcome
	logged.emit(event)


# The shield's bearer deals the damage back to whoever struck it.
func _read_damage_shield(reader: PacketReader) -> void:
	var event: CombatEvent = CombatEvent.new(Kind.DAMAGE_SHIELD)
	event.source = reader.u64()
	event.target = reader.u64()
	event.amount = reader.u32()
	event.school = reader.u32()
	logged.emit(event)


func _read_environment(reader: PacketReader) -> void:
	var event: CombatEvent = CombatEvent.new(Kind.ENVIRONMENT)
	event.target = reader.u64()
	event.environment = reader.u8()
	event.amount = reader.u32()
	event.absorbed = reader.u32()
	event.resisted = reader.i32()
	logged.emit(event)


# A hit that did no damage was soaked whole by an absorb, a resist or a block.
func _damage_outcome(event: CombatEvent) -> Outcome:
	if event.amount > 0:
		return Outcome.HIT
	if event.absorbed > 0:
		return Outcome.ABSORB
	if event.resisted > 0:
		return Outcome.RESIST
	if event.blocked > 0:
		return Outcome.BLOCK
	return Outcome.HIT


class CombatEvent:
	var kind: CombatEvents.Kind = CombatEvents.Kind.MELEE
	var outcome: CombatEvents.Outcome = CombatEvents.Outcome.HIT
	var source: int = 0
	var target: int = 0
	var spell: int = 0
	var amount: int = 0
	var school: int = 0
	var power: int = 0
	var environment: int = 0
	var critical: bool = false
	var glancing: bool = false
	var crushing: bool = false
	var absorbed: int = 0
	var resisted: int = 0
	var blocked: int = 0


	func _init(event_kind: CombatEvents.Kind) -> void:
		kind = event_kind
