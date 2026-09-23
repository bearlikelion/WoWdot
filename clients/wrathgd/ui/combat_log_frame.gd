@tool
class_name CombatLogFrame
extends DockedChatFrame

# Blizzard_CombatLog.lua hangs the filter bar across the log's top and shortens the log under it.
const QUICK_BAR_HEIGHT: float = 24.0
const COMBAT_COLOR: Color = Color(1.0, 1.0, 1.0)
const XP_COLOR: Color = Color(0.435, 0.435, 1.0)
const POWER_NAMES: Array[String] = [
	"MANA", "RAGE", "FOCUS", "ENERGY", "HAPPINESS", "RUNES", "RUNIC_POWER",
]
const SCHOOL_NAMES: Array[String] = [
	"PHYSICAL", "HOLY", "FIRE", "NATURE", "FROST", "SHADOW", "ARCANE",
]
const ENVIRONMENT_NAMES: Array[String] = ["FATIGUE", "DROWNING", "FALLING", "LAVA", "SLIME", "FIRE"]


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	%ChatFrame2TabText.text = WowStrings.get_text("COMBAT_LOG")
	WowClient.combat.logged.connect(_on_logged)
	var bar: Control = %CombatLogQuickButtonFrame_Custom
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		bar.set_anchor(side, 0.0)
	bar.position = Vector2.ZERO
	bar.size = Vector2(size.x, QUICK_BAR_HEIGHT)
	(_lines.get_parent() as Control).offset_top += QUICK_BAR_HEIGHT


func set_selected(value: bool) -> void:
	super(value)
	%CombatLogQuickButtonFrame_Custom.visible = value


# The line the stock client's combat log prints for an event, or "" when it prints none.
static func format(event: CombatEvents.CombatEvent) -> String:
	var hit: bool = event.outcome == CombatEvents.Outcome.HIT
	var swing: String = WowStrings.get_text("ACTION_SWING")
	match event.kind:
		CombatEvents.Kind.MELEE:
			if not hit:
				return _missed("SWING_MISSED", event, swing)
			return _full("SWING_DAMAGE", event, _damage(event), _result(event), swing)
		CombatEvents.Kind.SPELL:
			if not hit:
				return _missed("SPELL_MISSED", event)
			return _full("SPELL_DAMAGE", event, _damage(event), _result(event))
		CombatEvents.Kind.PERIODIC:
			if not hit:
				return ""
			return _full("SPELL_PERIODIC_DAMAGE", event, _damage(event), _result(event))
		CombatEvents.Kind.HEAL:
			return _full("SPELL_HEAL", event, str(event.amount), _result(event))
		CombatEvents.Kind.PERIODIC_HEAL:
			return _full("SPELL_PERIODIC_HEAL", event, str(event.amount), _result(event))
		CombatEvents.Kind.ENERGIZE:
			return _full("SPELL_ENERGIZE", event, str(event.amount))
		CombatEvents.Kind.PERIODIC_ENERGIZE:
			return _full("SPELL_PERIODIC_ENERGIZE", event, str(event.amount))
		CombatEvents.Kind.DAMAGE_SHIELD:
			return _full("DAMAGE_SHIELD", event, _damage(event), _result(event))
		CombatEvents.Kind.ENVIRONMENT:
			if event.environment >= ENVIRONMENT_NAMES.size():
				return ""
			var hazard: String = "ENVIRONMENTAL_DAMAGE_" + ENVIRONMENT_NAMES[event.environment]
			return _full(hazard, event, _damage(event), _result(event), _text("ACTION_" + hazard))
		CombatEvents.Kind.KILL:
			return _full("PARTY_KILL", event)
		CombatEvents.Kind.XP:
			if event.target == 0:
				return WowStrings.get_text("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED") % event.amount
			var text: String = WowStrings.get_text("COMBATLOG_XPGAIN_FIRSTPERSON")
			return text % [_name(event.target), event.amount]
		CombatEvents.Kind.DISPEL:
			var dispel: String = "SPELL_DISPEL_" + ("BUFF" if event.positive else "DEBUFF")
			var dispeller: String = WowAssets.spells.spell_name(event.extra_spell)
			var aura: String = WowAssets.spells.spell_name(event.spell)
			return _full(dispel, event, aura, "", dispeller, true)
		CombatEvents.Kind.INSTAKILL:
			return _full("SPELL_INSTAKILL", event)
		CombatEvents.Kind.ENCHANT:
			var item_name: String = WowClient.session.get_item_info(event.item).get("name", "")
			var enchant: String = "ENCHANT_REMOVED" if event.source == 0 else "ENCHANT_APPLIED"
			return _full(enchant, event, item_name, "", "", true)
	return ""


# Blizzard_CombatLog's full text mode: ACTION_<event>_FULL_TEXT filled in by position.
static func _full(
	key: String,
	event: CombatEvents.CombatEvent,
	value: String = "",
	result: String = "",
	spell: String = "",
	target_owns_value: bool = false,
) -> String:
	var template: String = _text("ACTION_%s_FULL_TEXT" % key)
	if template.is_empty():
		return ""
	var spell_name: String = spell
	if spell_name.is_empty() and event.spell:
		spell_name = WowAssets.spells.spell_name(event.spell)
	var source: String = _name(event.source) if event.source else WowStrings.get_text("UNKNOWN")
	if not spell_name.is_empty() and _text("ACTION_%s_POSSESSIVE" % key) == "1":
		source = _possessive(source)
	var target: String = _name(event.target) if event.target else WowStrings.get_text("UNKNOWN")
	if target_owns_value and event.target:
		target = _possessive(target)
	return WowStrings.format(template, [
		source, spell_name, _text("ACTION_" + key), target, value,
		" " + result if not result.is_empty() else "", _school(event.school),
		_power(event.power), event.amount, 0,
	])


# A miss names its kind, as ACTION_SWING_MISSED_DODGE_FULL_TEXT does, else the plain miss.
static func _missed(stem: String, event: CombatEvents.CombatEvent, spell: String = "") -> String:
	var kind: String = CombatEvents.Outcome.keys()[event.outcome]
	var key: String = "%s_%s" % [stem, kind]
	if _text("ACTION_%s_FULL_TEXT" % key).is_empty():
		key = stem
	return _full(key, event, "", _result(event), spell)


# TEXT_MODE_A_STRING_VALUE_SCHOOL: the amount and the school it hit with.
static func _damage(event: CombatEvents.CombatEvent) -> String:
	return WowStrings.format(
		_text("TEXT_MODE_A_STRING_VALUE_SCHOOL"), [event.amount, _school(event.school)]
	)


# CombatLog_String's result: resisted, blocked and absorbed amounts, then the kind of blow.
static func _result(event: CombatEvents.CombatEvent) -> String:
	var parts: PackedStringArray = []
	if event.resisted > 0:
		parts.append(_text("TEXT_MODE_A_STRING_RESULT_RESIST") % event.resisted)
	if event.blocked > 0:
		parts.append(_text("TEXT_MODE_A_STRING_RESULT_BLOCK") % event.blocked)
	if event.absorbed > 0:
		parts.append(_text("TEXT_MODE_A_STRING_RESULT_ABSORB") % event.absorbed)
	if event.glancing:
		parts.append(_text("TEXT_MODE_A_STRING_RESULT_GLANCING"))
	if event.crushing:
		parts.append(_text("TEXT_MODE_A_STRING_RESULT_CRUSHING"))
	if event.critical:
		parts.append(_text("TEXT_MODE_A_STRING_RESULT_CRITICAL"))
	return " ".join(parts)


# The lowest school in the mask names it, where the stock table also names the blends.
static func _school(mask: int) -> String:
	for i: int in SCHOOL_NAMES.size():
		if mask & (1 << i):
			return _text("STRING_SCHOOL_" + SCHOOL_NAMES[i])
	return _text("STRING_SCHOOL_PHYSICAL")


static func _power(power: int) -> String:
	return _text(POWER_NAMES[power]) if power >= 0 and power < POWER_NAMES.size() else ""


static func _possessive(unit_name: String) -> String:
	return WowStrings.format(_text("TEXT_MODE_A_STRING_POSSESSIVE"), [unit_name])


# A GlobalStrings entry, or nothing where the stock client has none.
static func _text(key: String) -> String:
	return WowStrings.get_text(key) if WowStrings.has_text(key) else ""


static func _name(guid: int) -> String:
	var unit_name: String = WowClient.session.get_object_name(guid)
	return unit_name if not unit_name.is_empty() else WowStrings.get_text("UNKNOWNOBJECT")


func _on_logged(event: CombatEvents.CombatEvent) -> void:
	var text: String = format(event)
	if not text.is_empty():
		add_message(text, XP_COLOR if event.kind == CombatEvents.Kind.XP else COMBAT_COLOR)
