class_name BeastTraining
extends RefCounted

const SPELL: int = 5149
# A Beast Training spell is a learn-spell effect aimed at the caster's pet.
const EFFECT_LEARN_SPELL: int = 36
const TARGET_CASTER_PET: int = 5
const SPELL_EFFECTS: int = 3
# CreatureFamily's two skill lines, the family's own abilities and those every pet shares.
const FAMILY_SKILL_COLUMNS: Array[int] = [5, 6]

static var _spells: WowDBC
static var _families: WowDBC
# Each pet ability's skill lines and SkillLineAbility training point cost.
static var _skill_lines: Dictionary[int, PackedInt32Array] = {}
static var _costs: Dictionary[int, int] = {}


## GetCraftInfo for Beast Training: what the hunter can teach the current pet.
static func abilities() -> Array[Dictionary]:
	_open()
	var session: WowSession = WowClient.session
	var pet: int = WowClient.pet.guid
	if pet == 0:
		return []
	var family_lines: Array[int] = _family_lines(pet)
	var known: Dictionary[int, bool] = {}
	for packed: int in WowClient.pet.spells:
		known[WowClient.pet.spell_of(packed)] = true
	var found: Array[Dictionary] = []
	for spell_id: int in session.get_known_spells():
		var taught: int = _taught(spell_id)
		if taught == 0 or not Array(_skill_lines.get(taught, PackedInt32Array())).any(
			func(line: int) -> bool: return line in family_lines
		):
			continue
		var cost: int = _costs.get(taught, 0) - _spent(taught, known)
		found.append({
			"spell": spell_id,
			"taught": taught,
			"name": WowAssets.spells.spell_name(taught),
			"rank": WowAssets.spells.rank(taught),
			"level": _spells.get_uint(_spells.find(spell_id), "SpellLevel"),
			"cost": maxi(cost, 0),
			"used": known.has(taught) or (cost <= 0 and _costs.get(taught, 0) > 0),
		})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["name"] < b["name"] if a["name"] != b["name"] else a["taught"] < b["taught"]
	)
	return found


## GetPetTrainingPoints, as what is left to spend; UNIT_TRAINING_POINTS stores -(points + 1).
static func points() -> int:
	var pet: int = WowClient.pet.guid
	if pet == 0:
		return 0
	var raw: int = WowClient.session.get_field(pet, "UNIT_TRAINING_POINTS")
	var signed: int = raw - (1 << 32) if raw >= 1 << 31 else raw
	return -signed - 1 if signed < 0 else -signed


# The pet ability a Beast Training spell teaches, or 0 for any other spell.
static func _taught(spell_id: int) -> int:
	var row: int = _spells.find(spell_id)
	if row < 0:
		return 0
	for i: int in SPELL_EFFECTS:
		if _spells.get_uint(row, "Effect%d" % i) == EFFECT_LEARN_SPELL \
		and _spells.get_uint(row, "EffectImplicitTargetA%d" % i) == TARGET_CASTER_PET:
			return _spells.get_uint(row, "EffectTriggerSpell%d" % i)
	return 0


# Pet::GetTPForSpell: a higher rank costs only what the pet has not already paid for the ability.
static func _spent(taught: int, known: Dictionary[int, bool]) -> int:
	var ability: String = WowAssets.spells.spell_name(taught)
	var spent: int = 0
	for spell_id: int in known:
		if WowAssets.spells.spell_name(spell_id) == ability:
			spent = maxi(spent, _costs.get(spell_id, 0))
	return spent


static func _family_lines(pet: int) -> Array[int]:
	var family: int = WowClient.session.get_creature_info(pet).get("family", 0)
	var row: int = _families.find(family) if family else -1
	var lines: Array[int] = []
	if row >= 0:
		for column: int in FAMILY_SKILL_COLUMNS:
			lines.append(_families.get_uint(row, column))
	return lines


static func _open() -> void:
	if _spells != null:
		return
	var archive: WowArchive = WowAssets.archive
	_spells = WowDBC.open(archive, "Spell")
	_families = WowDBC.open(archive, "CreatureFamily")
	var abilities_table: WowDBC = WowDBC.open(archive, "SkillLineAbility")
	for row: int in abilities_table.row_count():
		var spell_id: int = abilities_table.get_uint(row, "SpellID")
		var lines: PackedInt32Array = _skill_lines.get(spell_id, PackedInt32Array())
		lines.append(abilities_table.get_uint(row, "SkillLineID"))
		_skill_lines[spell_id] = lines
		_costs[spell_id] = maxi(
			_costs.get(spell_id, 0), abilities_table.get_uint(row, "ReqTrainPoints")
		)
