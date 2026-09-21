class_name TradeSkills
extends RefCounted

enum Difficulty { TRIVIAL, EASY, MEDIUM, OPTIMAL }

# SkillLine.dbc puts the nine primary gathering and crafting professions in this category.
const PROFESSION_CATEGORY: int = 11
# Cooking, first aid and fishing sit in their own category.
const SECONDARY_CATEGORY: int = 9
# A recipe makes its item through this spell effect.
const EFFECT_CREATE_ITEM: int = 24
# Enchanting's recipes make nothing; they put a lasting or a timed enchant on an item instead.
const ENCHANT_EFFECTS: Array[int] = [53, 54]
const REAGENT_SLOTS: int = 8
const EFFECT_SLOTS: int = 3
const MAX_SKILLS: int = 128
const SKILL_FIELDS: int = 3

static var _spells: WowDBC
static var _abilities: WowDBC
static var _skill_lines: WowDBC


## The professions the character has, each with its skill line, name and where its rank stands.
static func professions() -> Array[Dictionary]:
	_open()
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	var first: int = session.field_index("PLAYER_SKILL_INFO_1_1")
	var found: Array[Dictionary] = []
	for i: int in MAX_SKILLS:
		var id: int = session.get_field(guid, first + i * SKILL_FIELDS) & 0xFFFF
		var row: int = _skill_lines.find(id) if id else -1
		if row < 0 or _skill_lines.get_uint(row, "Category") not in [
			PROFESSION_CATEGORY, SECONDARY_CATEGORY,
		]:
			continue
		var ranks: int = session.get_field(guid, first + i * SKILL_FIELDS + 1)
		found.append({
			"skill_line": id,
			"name": _skill_lines.get_string(row, "Name"),
			"rank": ranks & 0xFFFF,
			"max_rank": ranks >> 16,
		})
	return found


## Every recipe the character knows in one profession, with its reagents and what it makes.
static func recipes(skill_line: int) -> Array[Dictionary]:
	_open()
	var known: Dictionary[int, bool] = {}
	for spell_id: int in WowClient.session.get_known_spells():
		known[spell_id] = true
	var found: Array[Dictionary] = []
	for row: int in _abilities.row_count():
		if _abilities.get_uint(row, "SkillLineID") != skill_line:
			continue
		var spell_id: int = _abilities.get_uint(row, "SpellID")
		if not known.has(spell_id):
			continue
		var recipe: Dictionary = _recipe(spell_id)
		if recipe.is_empty():
			continue
		recipe["trivial_high"] = _abilities.get_uint(row, "TrivialRankHigh")
		recipe["trivial_low"] = _abilities.get_uint(row, "TrivialRankLow")
		found.append(recipe)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
	return found


## How hard a recipe is at this rank, which is the colour the stock list draws it in.
static func difficulty(recipe: Dictionary, rank: int) -> Difficulty:
	var high: int = recipe["trivial_high"]
	var low: int = recipe["trivial_low"]
	if high > 0 and rank >= high:
		return Difficulty.TRIVIAL
	if low > 0 and rank >= low + (high - low) / 2:
		return Difficulty.EASY
	if low > 0 and rank >= low:
		return Difficulty.MEDIUM
	return Difficulty.OPTIMAL


## How many of each reagent the bags hold, against how many the recipe wants.
static func reagents_held(recipe: Dictionary) -> Array[Dictionary]:
	var counted: Dictionary[int, int] = {}
	for bag: int in Inventory.BAG_COUNT + 1:
		for slot: int in Inventory.container_size(bag):
			var item: int = Inventory.container_item(bag, slot)
			if item == 0:
				continue
			var entry: int = Inventory.entry(item)
			counted[entry] = counted.get(entry, 0) + Inventory.stack_count(item)
	var stock: Array[Dictionary] = []
	for reagent: Dictionary in recipe["reagents"]:
		stock.append({
			"item": reagent["item"], "need": reagent["count"],
			"held": counted.get(reagent["item"], 0),
		})
	return stock


static func can_make(recipe: Dictionary) -> bool:
	for reagent: Dictionary in reagents_held(recipe):
		if reagent["held"] < reagent["need"]:
			return false
	return true


# Crafting is an ordinary cast in 1.12, since the protocol has no tradeskill opcodes at all.
static func make(recipe: Dictionary) -> void:
	if WowAssets.spells.targets_item(recipe["spell"]):
		WowClient.targeting.begin_spell(recipe["spell"])
	else:
		WowClient.session.cast_spell(recipe["spell"])


static func _recipe(spell_id: int) -> Dictionary:
	var row: int = _spells.find(spell_id)
	if row < 0:
		return {}
	var product: int = 0
	var made: int = 1
	for i: int in EFFECT_SLOTS:
		if _spells.get_uint(row, "Effect%d" % i) != EFFECT_CREATE_ITEM:
			continue
		product = _spells.get_uint(row, "EffectItemType%d" % i)
		made = maxi(_spells.get_uint(row, "EffectBasePoints%d" % i) + 1, 1)
		break
	var enchants: bool = false
	for i: int in EFFECT_SLOTS:
		enchants = enchants or _spells.get_uint(row, "Effect%d" % i) in ENCHANT_EFFECTS
	if product == 0 and not enchants:
		return {}
	var reagents: Array[Dictionary] = []
	for i: int in REAGENT_SLOTS:
		var item: int = _spells.get_uint(row, "Reagent%d" % i)
		if item != 0:
			reagents.append({"item": item, "count": _spells.get_uint(row, "ReagentCount%d" % i)})
	return {
		"spell": spell_id,
		"name": _spells.get_string(row, "Name"),
		"icon": _spells.get_uint(row, "IconID"),
		"product": product,
		"made": made,
		"reagents": reagents,
	}


static func _open() -> void:
	if _spells != null:
		return
	var archive: WowArchive = WowAssets.archive
	_spells = WowDBC.open(archive, "Spell")
	_abilities = WowDBC.open(archive, "SkillLineAbility")
	_skill_lines = WowDBC.open(archive, "SkillLine")
