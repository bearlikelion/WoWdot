class_name SpellText
extends RefCounted

enum PowerType { MANA, RAGE, FOCUS, ENERGY }

const SPELL_ATTR_ON_NEXT_SWING: int = 0x4 | 0x400
const SPELL_ATTR_EX_CHANNELED: int = 0x4 | 0x40
const RANGE_SELF: int = 1
const RANGE_FLAG_MELEE: int = 0x1
const POWER_COSTS: Dictionary[PowerType, String] = {
	PowerType.MANA: "MANA_COST", PowerType.RAGE: "RAGE_COST",
	PowerType.FOCUS: "FOCUS_COST", PowerType.ENERGY: "ENERGY_COST",
}
# Rage costs are stored at ten times the value players see.
const RAGE_SCALE: int = 10
# $12345s1, $/10;s1, $d, $lsingular:plural; and the like in Spell.dbc descriptions.
const TOKEN: String = "\\$(?:/(\\d+);)?(\\d+)?([a-zA-Z])(\\d)?"

static var _spells: WowDBC
static var _casts: WowDBC
static var _durations: WowDBC
static var _ranges: WowDBC
static var _radii: WowDBC
static var _token: RegEx


# A description or aura tooltip with its $ tokens replaced by this rank's numbers.
static func describe(spell_id: int, column: String = "Description") -> String:
	_open()
	var row: int = _spells.find(spell_id)
	if row < 0:
		return ""
	var text: String = _spells.get_string(row, column)
	text = _plurals(text)
	var out: String = ""
	var at: int = 0
	for found: RegExMatch in _token.search_all(text):
		out += text.substr(at, found.get_start() - at)
		var source: int = found.get_string(2).to_int() if not found.get_string(2).is_empty() else spell_id
		var divisor: int = found.get_string(1).to_int() if not found.get_string(1).is_empty() else 1
		var index: int = maxi(found.get_string(4).to_int(), 1) - 1
		out += _value(source, found.get_string(3).to_lower(), index, divisor)
		at = found.get_end()
	return out + text.substr(at)


static func cost(spell_id: int) -> String:
	_open()
	var row: int = _spells.find(spell_id)
	var amount: int = _spells.get_uint(row, "ManaCost") if row >= 0 else 0
	if amount == 0:
		return ""
	var power: PowerType = _spells.get_uint(row, "PowerType") as PowerType
	if power == PowerType.RAGE:
		amount = floori(amount / float(RAGE_SCALE))
	return WowStrings.get_text(POWER_COSTS.get(power, "MANA_COST")) % amount


static func range_text(spell_id: int) -> String:
	_open()
	var row: int = _spells.find(spell_id)
	var range_row: int = _ranges.find(_spells.get_uint(row, "RangeIndex")) if row >= 0 else -1
	if range_row < 0 or _ranges.get_uint(range_row, "ID") == RANGE_SELF:
		return ""
	# Melee ranges show their SpellRange name ("Melee Range"); the rest show yards.
	if _ranges.get_uint(range_row, "Flags") & RANGE_FLAG_MELEE:
		return _ranges.get_string(range_row, "Name")
	return WowStrings.get_text("SPELL_RANGE") % str(roundi(_ranges.get_float(range_row, "MaxRange")))


static func cast_text(spell_id: int) -> String:
	_open()
	var row: int = _spells.find(spell_id)
	if row < 0:
		return ""
	if _spells.get_uint(row, "Attributes") & SPELL_ATTR_ON_NEXT_SWING:
		return WowStrings.get_text("SPELL_ON_NEXT_SWING")
	if _spells.get_uint(row, "AttributesEx") & SPELL_ATTR_EX_CHANNELED:
		return WowStrings.get_text("SPELL_CAST_CHANNELED")
	var cast_row: int = _casts.find(_spells.get_uint(row, "CastingTimeIndex"))
	var msec: int = _casts.get_uint(cast_row, "Base") if cast_row >= 0 else 0
	if msec == 0:
		return WowStrings.get_text("SPELL_CAST_TIME_INSTANT_NO_MANA")
	return _format("SPELL_CAST_TIME_SEC", msec / 1000.0)


static func cooldown_text(spell_id: int) -> String:
	_open()
	var row: int = _spells.find(spell_id)
	var msec: int = 0
	if row >= 0:
		msec = maxi(_spells.get_uint(row, "RecoveryTime"), _spells.get_uint(row, "CategoryRecoveryTime"))
	if msec == 0:
		return ""
	if msec >= 60000:
		return _format("SPELL_RECAST_TIME_MIN", msec / 60000.0)
	return _format("SPELL_RECAST_TIME_SEC", msec / 1000.0)


static func duration_text(msec: int) -> String:
	var seconds: int = roundi(msec / 1000.0)
	if seconds >= 3600:
		return "%d hrs" % roundi(seconds / 3600.0)
	if seconds >= 60:
		return "%d min" % roundi(seconds / 60.0)
	return "%d sec" % seconds


static func _value(spell_id: int, token: String, index: int, divisor: int) -> String:
	var row: int = _spells.find(spell_id)
	if row < 0:
		return ""
	var base: int = _spells.get_int(row, "EffectBasePoints%d" % index)
	var dice: int = _spells.get_int(row, "EffectBaseDice%d" % index)
	var sides: int = _spells.get_int(row, "EffectDieSides%d" % index)
	match token:
		"s", "m":
			# The stock client prints amounts unsigned: a -40% slow reads "by 40%".
			var low: int = absi(base + dice)
			var high: int = absi(base + dice * maxi(sides, 1))
			if token == "m" or high <= low:
				return str(floori(low / float(divisor)))
			return "%d to %d" % [floori(low / float(divisor)), floori(high / float(divisor))]
		"o":
			var amplitude: int = _spells.get_uint(row, "EffectAmplitude%d" % index)
			var ticks: int = floori(_duration_msec(row) / float(amplitude)) if amplitude > 0 else 1
			return str(floori((base + dice) * ticks / float(divisor)))
		"t":
			return str(_spells.get_uint(row, "EffectAmplitude%d" % index) / 1000.0)
		"d":
			return duration_text(_duration_msec(row))
		"a":
			var radius: int = _radii.find(_spells.get_uint(row, "EffectRadiusIndex%d" % index))
			return str(roundi(_radii.get_float(radius, "Radius"))) if radius >= 0 else ""
		"h":
			return str(_spells.get_uint(row, "ProcChance"))
		"n":
			return str(_spells.get_uint(row, "ProcCharges"))
		"x":
			return str(_spells.get_uint(row, "EffectChainTarget%d" % index))
	return ""


# The stock strings use C's %.3g, which GDScript formatting lacks: 1.5 stays 1.5, 3.0 becomes 3.
static func _format(key: String, value: float) -> String:
	var whole: bool = is_equal_approx(value, roundf(value))
	var number: String = str(roundi(value)) if whole else String.num(value, 2)
	return WowStrings.get_text(key).replace("%.3g", number)


static func _duration_msec(row: int) -> int:
	var duration: int = _durations.find(_spells.get_uint(row, "DurationIndex"))
	return _durations.get_int(duration, "Base") if duration >= 0 else 0


# $lsingular:plural; always reads as the plural, since tooltip numbers are rarely one.
static func _plurals(text: String) -> String:
	var plural: RegEx = RegEx.create_from_string("\\$[lL]([^:;]*):([^;]*);")
	return plural.sub(text, "$2", true)


static func _open() -> void:
	if _spells != null:
		return
	var archive: WowArchive = WowAssets.archive
	_spells = WowDBC.open(archive, "Spell")
	_casts = WowDBC.open(archive, "SpellCastTimes")
	_durations = WowDBC.open(archive, "SpellDuration")
	_ranges = WowDBC.open(archive, "SpellRange")
	_radii = WowDBC.open(archive, "SpellRadius")
	_token = RegEx.create_from_string(TOKEN)
