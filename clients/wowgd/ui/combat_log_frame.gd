@tool
class_name CombatLogFrame
extends DockedChatFrame

# Template parts in order; a side that is "you" is written into the template and dropped.
enum Slot { SOURCE, TARGET, SPELL, AMOUNT, SCHOOL, POWER }

const COMBAT_COLOR: Color = Color(1.0, 1.0, 1.0)
const XP_COLOR: Color = Color(0.435, 0.435, 1.0)
const POWER_NAMES: Array[String] = ["MANA", "RAGE", "FOCUS", "ENERGY", "HAPPINESS"]
const ENVIRONMENT_NAMES: Array[String] = ["FATIGUE", "DROWNING", "FALLING", "LAVA", "SLIME", "FIRE"]
# GlobalStrings stem for a spell that failed to land, per outcome.
const SPELL_FAILURES: Dictionary[CombatEvents.Outcome, String] = {
	CombatEvents.Outcome.MISS: "SPELLMISS", CombatEvents.Outcome.DODGE: "SPELLDODGED",
	CombatEvents.Outcome.PARRY: "SPELLPARRIED", CombatEvents.Outcome.BLOCK: "SPELLBLOCKED",
	CombatEvents.Outcome.EVADE: "SPELLEVADED", CombatEvents.Outcome.IMMUNE: "SPELLIMMUNE",
	CombatEvents.Outcome.DEFLECT: "SPELLDEFLECTED", CombatEvents.Outcome.RESIST: "SPELLRESIST",
	CombatEvents.Outcome.ABSORB: "SPELLLOGABSORB", CombatEvents.Outcome.REFLECT: "SPELLREFLECT",
}
const MELEE_FAILURES: Dictionary[CombatEvents.Outcome, String] = {
	CombatEvents.Outcome.MISS: "MISSED", CombatEvents.Outcome.DODGE: "VSDODGE",
	CombatEvents.Outcome.PARRY: "VSPARRY", CombatEvents.Outcome.BLOCK: "VSBLOCK",
	CombatEvents.Outcome.EVADE: "VSEVADE", CombatEvents.Outcome.IMMUNE: "VSIMMUNE",
	CombatEvents.Outcome.DEFLECT: "VSDEFLECT", CombatEvents.Outcome.RESIST: "VSRESIST",
	CombatEvents.Outcome.ABSORB: "VSABSORB",
}


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	window_name = WowStrings.get_text("COMBAT_LOG")
	WowClient.combat.logged.connect(_on_logged)


# The line the stock client's combat log prints for an event, or "" when it prints none.
static func format(event: CombatEvents.CombatEvent) -> String:
	var hit: bool = event.outcome == CombatEvents.Outcome.HIT
	match event.kind:
		CombatEvents.Kind.MELEE:
			if not hit:
				var sides: Array[Slot] = [Slot.SOURCE, Slot.TARGET]
				return _line(MELEE_FAILURES.get(event.outcome, "MISSED"), sides, event)
			var stem: String = "COMBATHIT" + _crit(event) + _school_stem(event)
			var slots: Array[Slot] = [Slot.SOURCE, Slot.TARGET, Slot.AMOUNT, Slot.SCHOOL]
			return _line(stem, slots, event) + _trailers(event)
		CombatEvents.Kind.SPELL:
			if not hit:
				var failure: String = SPELL_FAILURES.get(event.outcome, "SPELLMISS")
				var sides: Array[Slot] = [Slot.SOURCE, Slot.SPELL, Slot.TARGET]
				return _line(failure, sides, event)
			var stem: String = "SPELLLOG" + _crit(event) + _school_stem(event)
			var slots: Array[Slot] = [
				Slot.SOURCE, Slot.SPELL, Slot.TARGET, Slot.AMOUNT, Slot.SCHOOL,
			]
			return _line(stem, slots, event) + _trailers(event)
		CombatEvents.Kind.PERIODIC:
			if not hit:
				return ""
			var slots: Array[Slot] = [
				Slot.TARGET, Slot.AMOUNT, Slot.SCHOOL, Slot.SOURCE, Slot.SPELL,
			]
			return _line("PERIODICAURADAMAGE", slots, event) + _trailers(event)
		CombatEvents.Kind.HEAL:
			var stem: String = "HEALEDCRIT" if event.critical else "HEALED"
			var slots: Array[Slot] = [Slot.SOURCE, Slot.SPELL, Slot.TARGET, Slot.AMOUNT]
			return _line(stem, slots, event)
		CombatEvents.Kind.PERIODIC_HEAL:
			var slots: Array[Slot] = [Slot.TARGET, Slot.AMOUNT, Slot.SOURCE, Slot.SPELL]
			return _line("PERIODICAURAHEAL", slots, event)
		CombatEvents.Kind.ENERGIZE, CombatEvents.Kind.PERIODIC_ENERGIZE:
			var slots: Array[Slot] = [
				Slot.TARGET, Slot.AMOUNT, Slot.POWER, Slot.SOURCE, Slot.SPELL,
			]
			return _line("POWERGAIN", slots, event)
		CombatEvents.Kind.DAMAGE_SHIELD:
			var slots: Array[Slot] = [Slot.SOURCE, Slot.AMOUNT, Slot.SCHOOL, Slot.TARGET]
			return _line("DAMAGESHIELD", slots, event)
		CombatEvents.Kind.ENVIRONMENT:
			if event.environment >= ENVIRONMENT_NAMES.size():
				return ""
			var you: bool = event.target == WowClient.session.get_player_guid()
			var key: String = "VSENVIRONMENTALDAMAGE_%s_%s" % [
				ENVIRONMENT_NAMES[event.environment], "SELF" if you else "OTHER",
			]
			var args: Array = [event.amount] if you else [_name(event.target), event.amount]
			return WowStrings.get_text(key) % args + _trailers(event)
		CombatEvents.Kind.KILL:
			if event.source == WowClient.session.get_player_guid():
				return WowStrings.get_text("SELFKILLOTHER") % _name(event.target)
			var names: Array = [_name(event.target), _name(event.source)]
			return WowStrings.get_text("PARTYKILLOTHER") % names
		CombatEvents.Kind.XP:
			if event.target == 0:
				return WowStrings.get_text("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED") % event.amount
			var text: String = WowStrings.get_text("COMBATLOG_XPGAIN_FIRSTPERSON")
			return text % [_name(event.target), event.amount]
		CombatEvents.Kind.DISPEL:
			var aura: String = WowAssets.spells.spell_name(event.spell)
			if event.target == WowClient.session.get_player_guid():
				return WowStrings.get_text("AURADISPELSELF") % aura
			return WowStrings.get_text("AURADISPELOTHER") % [_name(event.target), aura]
		CombatEvents.Kind.INSTAKILL:
			var killer: String = WowAssets.spells.spell_name(event.spell)
			if event.target == WowClient.session.get_player_guid():
				return WowStrings.get_text("INSTAKILLSELF") % killer
			return WowStrings.get_text("INSTAKILLOTHER") % [_name(event.target), killer]
		CombatEvents.Kind.ENCHANT:
			return _enchant_line(event)
	return ""


static func _line(stem: String, slots: Array[Slot], event: CombatEvents.CombatEvent) -> String:
	var me: int = WowClient.session.get_player_guid()
	var from_me: bool = event.source == me
	var to_me: bool = event.target == me
	var args: Array = []
	for slot: Slot in slots:
		match slot:
			Slot.SOURCE:
				if not from_me:
					args.append(_name(event.source))
			Slot.TARGET:
				if not to_me:
					args.append(_name(event.target))
			Slot.SPELL:
				args.append(WowAssets.spells.spell_name(event.spell))
			Slot.AMOUNT:
				args.append(event.amount)
			Slot.SCHOOL:
				if event.school != 0 or stem.begins_with("PERIODIC") or stem == "DAMAGESHIELD":
					args.append(WowStrings.get_text("SPELL_SCHOOL%d_NAME" % event.school))
			Slot.POWER:
				args.append(WowStrings.get_text(POWER_NAMES[clampi(event.power, 0, 4)]))
	var key: String = stem + ("SELF" if from_me else "OTHER") + ("SELF" if to_me else "OTHER")
	return WowStrings.get_text(key) % args


# A zero caster means the enchant faded rather than landed.
static func _enchant_line(event: CombatEvents.CombatEvent) -> String:
	var me: int = WowClient.session.get_player_guid()
	var mine: bool = event.target == me
	var item_name: String = WowClient.session.get_item_info(event.item).get("name", "")
	var args: Array = [WowAssets.spells.spell_name(event.spell)]
	if not mine:
		args.append(_name(event.target))
	args.append(item_name)
	if event.source == 0:
		return WowStrings.get_text("ITEMENCHANTMENTREMOVE" + ("SELF" if mine else "OTHER")) % args
	if event.source != me:
		args.push_front(_name(event.source))
	var key: String = "ITEMENCHANTMENTADD" + ("SELF" if event.source == me else "OTHER")
	return WowStrings.get_text(key + ("SELF" if mine else "OTHER")) % args


static func _crit(event: CombatEvents.CombatEvent) -> String:
	return "CRIT" if event.critical else ""


static func _school_stem(event: CombatEvents.CombatEvent) -> String:
	return "SCHOOL" if event.school != 0 else ""


static func _trailers(event: CombatEvents.CombatEvent) -> String:
	var text: String = ""
	if event.resisted > 0:
		text += WowStrings.get_text("RESIST_TRAILER") % event.resisted
	if event.blocked > 0:
		text += WowStrings.get_text("BLOCK_TRAILER") % event.blocked
	if event.absorbed > 0:
		text += WowStrings.get_text("ABSORB_TRAILER") % event.absorbed
	if event.glancing:
		text += WowStrings.get_text("GLANCING_TRAILER")
	if event.crushing:
		text += WowStrings.get_text("CRUSHING_TRAILER")
	return text


static func _name(guid: int) -> String:
	var unit_name: String = WowClient.session.get_object_name(guid)
	return unit_name if not unit_name.is_empty() else WowStrings.get_text("UNKNOWNOBJECT")


func _on_logged(event: CombatEvents.CombatEvent) -> void:
	var text: String = format(event)
	if not text.is_empty():
		add_message(text, XP_COLOR if event.kind == CombatEvents.Kind.XP else COMBAT_COLOR)
