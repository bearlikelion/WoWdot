class_name CombatFeedback
extends RefCounted

# COMBATFEEDBACK_FADEINTIME, _HOLDTIME and _FADEOUTTIME from CombatFeedback.lua.
const FADE_IN: float = 0.2
const HOLD: float = 0.7
const FADE_OUT: float = 0.3
const SPELL_COLOR: Color = Color(1.0, 1.0, 0.0)
const HEAL_COLOR: Color = Color(0.0, 1.0, 0.0)
const ENERGIZE_COLOR: Color = Color(0.41, 0.8, 0.94)

var _label: Label
var _fade: Tween


func _init(label: Label) -> void:
	_label = label


# CombatFeedback_OnCombatEvent: flashes the event's number or word over the portrait.
func show_event(event: CombatEvents.CombatEvent) -> void:
	var look: Dictionary = appearance(event)
	if look.is_empty():
		return
	_label.text = look["text"]
	_label.self_modulate = look["color"]
	_label.modulate.a = 0.0
	_label.pivot_offset = _label.get_minimum_size() / 2.0
	_label.scale = Vector2.ONE * float(look["size"])
	_label.show()
	if _fade:
		_fade.kill()
	_fade = _label.create_tween()
	_fade.tween_property(_label, "modulate:a", 1.0, FADE_IN)
	_fade.tween_interval(HOLD)
	_fade.tween_property(_label, "modulate:a", 0.0, FADE_OUT)
	_fade.tween_callback(_label.hide)


# The text, colour and size scale CombatFeedback shows for an event, or {} for none.
static func appearance(event: CombatEvents.CombatEvent) -> Dictionary:
	var size: float = 1.0
	var color: Color = Color.WHITE
	var text: String = ""
	match event.kind:
		CombatEvents.Kind.KILL, CombatEvents.Kind.XP:
			return {}
		CombatEvents.Kind.HEAL, CombatEvents.Kind.PERIODIC_HEAL:
			text = str(event.amount)
			color = HEAL_COLOR
			size = 1.5 if event.critical else 1.0
		CombatEvents.Kind.ENERGIZE, CombatEvents.Kind.PERIODIC_ENERGIZE:
			text = str(event.amount)
			color = ENERGIZE_COLOR
		_:
			match event.outcome:
				CombatEvents.Outcome.HIT:
					if event.amount <= 0:
						return {}
					text = str(event.amount)
					if event.critical or event.crushing:
						size = 1.5
					elif event.glancing:
						size = 0.75
					if event.school > 0:
						color = SPELL_COLOR
				CombatEvents.Outcome.ABSORB, CombatEvents.Outcome.BLOCK, \
				CombatEvents.Outcome.RESIST:
					size = 0.75
					text = outcome_text(event.outcome)
				CombatEvents.Outcome.IMMUNE:
					size = 0.5
					text = outcome_text(event.outcome)
				_:
					text = outcome_text(event.outcome)
	return {"text": text, "color": color, "size": size}


# MISS, DODGE, PARRY and the rest are GlobalStrings named after the outcome.
static func outcome_text(outcome: CombatEvents.Outcome) -> String:
	return WowStrings.get_text(CombatEvents.Outcome.find_key(outcome))
