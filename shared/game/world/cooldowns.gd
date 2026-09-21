class_name Cooldowns
extends RefCounted

signal changed

# SMSG_ITEM_COOLDOWN carries no duration; the stock client hardcodes this one.
const ITEM_COOLDOWN_MSEC: int = 30000

var _spells: SpellInfo
# Start and duration in msec, per spell and per global cooldown category.
var _by_spell: Dictionary[int, Vector2i] = {}
var _by_category: Dictionary[int, Vector2i] = {}


func _init(session: WowSession, spells: SpellInfo) -> void:
	_spells = spells
	session.spell_cooldown.connect(_on_spell_cooldown)
	session.packet_received.connect(_on_packet_received)
	session.spell_cast_started.connect(_on_player_cast.bind(session))
	session.spell_cast_finished.connect(_on_player_cast_finished.bind(session))


# Start and duration of whichever cooldown ends last for the spell, or zero.
func get_cooldown(spell_id: int) -> Vector2i:
	var own: Vector2i = _by_spell.get(spell_id, Vector2i.ZERO)
	var shared: Vector2i = _by_category.get(_spells.global_cooldown_category(spell_id), Vector2i.ZERO)
	return own if own.x + own.y >= shared.x + shared.y else shared


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode == "SMSG_ITEM_COOLDOWN" and payload.size() >= 12:
		_on_spell_cooldown(payload.decode_u32(8), ITEM_COOLDOWN_MSEC)


func _on_spell_cooldown(spell_id: int, cooldown_msec: int) -> void:
	_by_spell[spell_id] = Vector2i(Time.get_ticks_msec(), cooldown_msec)
	changed.emit()


func _on_player_cast(caster: int, spell_id: int, _cast_time_msec: int, session: WowSession) -> void:
	if caster == session.get_player_guid():
		_start_global(spell_id)


# Instant spells only arrive as SMSG_SPELL_GO; cast-time spells already started the GCD.
func _on_player_cast_finished(
	caster: int, spell_id: int, _targets: PackedInt64Array, session: WowSession,
) -> void:
	if caster == session.get_player_guid() and _spells.cast_time_msec(spell_id) == 0:
		_start_global(spell_id)


func _start_global(spell_id: int) -> void:
	var gcd: int = _spells.global_cooldown_msec(spell_id)
	var category: int = _spells.global_cooldown_category(spell_id)
	if gcd > 0 and category > 0:
		_by_category[category] = Vector2i(Time.get_ticks_msec(), gcd)
		changed.emit()
