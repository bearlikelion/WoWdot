class_name CombatText
extends Control

# Blizzard_CombatText.lua in float mode 1: lines rise from 384 to 609 over UIParent's bottom.
const SCROLL_TIME: float = 1.9
const FADE_OUT_TIME: float = 1.3
const TEXT_HEIGHT: float = 25.0
const CRIT_MIN_HEIGHT: float = 30.0
const CRIT_MAX_HEIGHT: float = 60.0
const CRIT_SCALE_TIME: float = 0.05
const CRIT_SHRINK_TIME: float = 0.2
const STAGGER_RANGE: float = 20.0
# A line's 16 units plus COMBAT_TEXT_SPACING keep new lines clear of the ones rising above.
const LINE_GAP: float = 26.0
const MAX_OFFSET: float = 130.0
const START_Y: float = 384.0
const END_Y: float = 609.0
const LOW_THRESHOLD: float = 0.2
const UNIT_FLAG_IN_COMBAT: int = 0x80000
const MANA: int = 0
# COMBAT_TEXT_TYPE_INFO colours of the message types the stock options show.
const DAMAGE_COLOR: Color = Color(1.0, 0.1, 0.1)
const SPELL_DAMAGE_COLOR: Color = Color(0.79, 0.3, 0.85)
const HEAL_COLOR: Color = Color(0.1, 1.0, 0.1)

var _messages: Array[Message] = []
var _in_combat: bool = false
var _low_health: bool = false
var _low_mana: bool = false


func _ready() -> void:
	WowClient.combat.logged.connect(_on_combat_logged)
	WowClient.session.object_updated.connect(_on_object_updated)


# CombatText_OnUpdate.
func _process(delta: float) -> void:
	for message: Message in _messages.duplicate():
		message.elapsed += delta
		if message.elapsed >= SCROLL_TIME:
			_remove(message)
			continue
		message.y = message.start_y + (message.end_y - START_Y) * message.elapsed / SCROLL_TIME
		if message.elapsed >= FADE_OUT_TIME:
			var fade: float = (message.elapsed - FADE_OUT_TIME) / (SCROLL_TIME - FADE_OUT_TIME)
			message.label.modulate.a = maxf(1.0 - fade, 0.0)
		_place(message)


# CombatText_AddMessage: a new line starts below the lowest line still rising.
func add_message(text: String, color: Color, crit: bool = false, staggered: bool = false) -> void:
	var message: Message = Message.new()
	message.label = _free_label()
	message.label.text = text
	message.label.self_modulate = color
	message.label.modulate.a = 1.0
	message.crit = crit
	var bottom: float = START_Y - (CRIT_MIN_HEIGHT if crit else TEXT_HEIGHT)
	var lowest: float = bottom
	for other: Message in _messages:
		if lowest >= other.y - LINE_GAP:
			lowest = other.y - LINE_GAP
	if lowest < START_Y - MAX_OFFSET:
		lowest = bottom
	message.start_y = lowest
	message.y = lowest
	message.end_y = START_Y if crit else END_Y
	if staggered:
		message.x = randi_range(0, int(STAGGER_RANGE)) - STAGGER_RANGE / 2.0
	_messages.append(message)
	message.label.show()
	_place(message)


# SetPoint("TOP", UIParent, "BOTTOM", x, y), with crits swelling to 60 and back to 30.
func _place(message: Message) -> void:
	var height: float = TEXT_HEIGHT
	if message.crit:
		if message.elapsed <= CRIT_SCALE_TIME:
			height = lerpf(CRIT_MIN_HEIGHT, CRIT_MAX_HEIGHT, message.elapsed / CRIT_SCALE_TIME)
		elif message.elapsed <= CRIT_SHRINK_TIME:
			var shrink: float = (message.elapsed - CRIT_SCALE_TIME) \
			/ (CRIT_SHRINK_TIME - CRIT_SCALE_TIME)
			height = lerpf(CRIT_MAX_HEIGHT, CRIT_MIN_HEIGHT, shrink)
		else:
			height = CRIT_MIN_HEIGHT
	var label: Label = message.label
	label.size = Vector2.ZERO
	label.pivot_offset = Vector2(label.size.x / 2.0, 0.0)
	label.scale = Vector2.ONE * height / TEXT_HEIGHT
	label.position = Vector2(size.x / 2.0 + message.x - label.size.x / 2.0, size.y - message.y)


func _free_label() -> Label:
	for label: Label in get_children():
		if not label.visible:
			return label
	var oldest: Label = _messages[0].label
	_remove(_messages[0])
	return oldest


func _remove(message: Message) -> void:
	_messages.erase(message)
	message.label.hide()


# COMBAT_TEXT_UPDATE for the player: DAMAGE, DAMAGE_CRIT, SPELL_DAMAGE, HEAL and PERIODIC_HEAL.
func _on_combat_logged(event: CombatEvents.CombatEvent) -> void:
	var me: int = WowClient.session.get_player_guid()
	if event.target != me or event.outcome != CombatEvents.Outcome.HIT or event.amount <= 0:
		return
	match event.kind:
		CombatEvents.Kind.MELEE, CombatEvents.Kind.ENVIRONMENT:
			add_message("-%d" % event.amount, DAMAGE_COLOR, event.critical, not event.critical)
		CombatEvents.Kind.SPELL, CombatEvents.Kind.PERIODIC, CombatEvents.Kind.DAMAGE_SHIELD:
			add_message("-%d" % event.amount, SPELL_DAMAGE_COLOR)
		CombatEvents.Kind.HEAL:
			add_message("+%d" % event.amount, HEAL_COLOR, event.critical)
		CombatEvents.Kind.PERIODIC_HEAL:
			add_message("+%d" % event.amount, HEAL_COLOR)


# PLAYER_REGEN_DISABLED and _ENABLED, and the low health and mana warnings.
func _on_object_updated(guid: int) -> void:
	var session: WowSession = WowClient.session
	if guid != session.get_player_guid():
		return
	var in_combat: bool = (session.get_field(guid, "UNIT_FIELD_FLAGS") & UNIT_FLAG_IN_COMBAT) != 0
	if in_combat != _in_combat:
		_in_combat = in_combat
		var key: String = "ENTERING_COMBAT" if in_combat else "LEAVING_COMBAT"
		add_message(WowStrings.get_text(key), DAMAGE_COLOR)
	var health: float = session.get_field(guid, "UNIT_FIELD_HEALTH")
	var max_health: float = maxi(session.get_field(guid, "UNIT_FIELD_MAXHEALTH"), 1)
	var low_health: bool = health > 0.0 and health / max_health <= LOW_THRESHOLD
	if low_health and not _low_health:
		add_message(WowStrings.get_text("HEALTH_LOW"), DAMAGE_COLOR)
	_low_health = low_health
	var power_type: int = (session.get_field(guid, "UNIT_FIELD_BYTES_0") >> 24) & 0xFF
	var mana: float = session.get_field(guid, "UNIT_FIELD_POWER1")
	var max_mana: float = maxi(session.get_field(guid, "UNIT_FIELD_MAXPOWER1"), 1)
	var low_mana: bool = power_type == MANA and mana / max_mana <= LOW_THRESHOLD
	if low_mana and not _low_mana:
		add_message(WowStrings.get_text("MANA_LOW"), DAMAGE_COLOR)
	_low_mana = low_mana


class Message:
	var label: Label
	var elapsed: float = 0.0
	var x: float = 0.0
	var y: float = 0.0
	var start_y: float = 0.0
	var end_y: float = 0.0
	var crit: bool = false
