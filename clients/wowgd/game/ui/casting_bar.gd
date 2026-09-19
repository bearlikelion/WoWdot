class_name CastingBar
extends TextureProgressBar

enum Mode { IDLE, CASTING, CHANNELING, FINISHING }

const CASTING_COLOR: Color = Color(1.0, 0.7, 0.0)
const SUCCESS_COLOR: Color = Color(0.0, 1.0, 0.0)
const FAILURE_COLOR: Color = Color(1.0, 0.0, 0.0)
# CASTING_BAR_ALPHA_STEP and CASTING_BAR_FLASH_STEP were per frame at 60 fps; these are per second.
const FADE_PER_SECOND: float = 3.0
const FLASH_PER_SECOND: float = 12.0
const HOLD_SECONDS: float = 1.0
const FAILED_TEXT: String = "Failed"
const INTERRUPTED_TEXT: String = "Interrupted"

# The player's spell being cast or channelled, or 0.
var spell_id: int = 0

var _mode: Mode = Mode.IDLE
var _start: float = 0.0
var _end: float = 0.0
var _hold_until: float = 0.0
var _flashing: bool = false

@onready var _text: Label = %CastingBarText
@onready var _spark: TextureRect = %CastingBarSpark
@onready var _flash: TextureRect = %CastingBarFlash


func _ready() -> void:
	min_value = 0.0
	max_value = 1.0
	var session: WowSession = WowClient.session
	session.spell_cast_started.connect(_on_cast_started)
	session.spell_cast_finished.connect(_on_cast_finished)
	session.spell_cast_failed.connect(_on_cast_failed)
	session.spell_cast_delayed.connect(_on_cast_delayed)
	session.spell_channel_started.connect(_on_channel_started)
	session.spell_channel_updated.connect(_on_channel_updated)
	hide()


func _process(delta: float) -> void:
	var now: float = _now()
	match _mode:
		Mode.CASTING:
			value = clampf((now - _start) / maxf(_end - _start, 0.001), 0.0, 1.0)
			_spark.position.x = value * size.x - _spark.size.x / 2.0
		Mode.CHANNELING:
			value = clampf((_end - now) / maxf(_end - _start, 0.001), 0.0, 1.0)
			_spark.position.x = value * size.x - _spark.size.x / 2.0
			if now >= _end:
				_finish(SUCCESS_COLOR, "", false)
		Mode.FINISHING:
			if _flashing:
				_flash.modulate.a = minf(_flash.modulate.a + FLASH_PER_SECOND * delta, 1.0)
				_flashing = _flash.modulate.a < 1.0
			elif now >= _hold_until:
				modulate.a -= FADE_PER_SECOND * delta
				if modulate.a <= 0.0:
					_mode = Mode.IDLE
					hide()


func _begin(mode: Mode, spell: int, duration_msec: int) -> void:
	spell_id = spell
	_mode = mode
	_start = _now()
	_end = _start + duration_msec / 1000.0
	tint_progress = CASTING_COLOR
	_text.text = WowAssets.spells.spell_name(spell)
	_spark.show()
	_flash.hide()
	modulate.a = 1.0
	show()


# Success flashes before fading; failure holds its red bar for a moment.
func _finish(color: Color, label: String, flash: bool) -> void:
	spell_id = 0
	_mode = Mode.FINISHING
	value = 1.0
	tint_progress = color
	_spark.hide()
	if not label.is_empty():
		_text.text = label
	_flashing = flash
	_flash.visible = flash
	_flash.modulate.a = 0.0
	_hold_until = _now() + (0.0 if flash else HOLD_SECONDS)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _is_player(caster: int) -> bool:
	return caster == WowClient.session.get_player_guid()


func _on_cast_started(caster: int, spell_id: int, cast_time_msec: int) -> void:
	if _is_player(caster) and cast_time_msec > 0:
		_begin(Mode.CASTING, spell_id, cast_time_msec)


func _on_cast_finished(caster: int, _spell_id: int) -> void:
	if _is_player(caster) and _mode == Mode.CASTING:
		_finish(SUCCESS_COLOR, "", true)


func _on_cast_failed(caster: int, _spell_id: int, reason: int) -> void:
	if _is_player(caster) and _mode == Mode.CASTING:
		_finish(FAILURE_COLOR, INTERRUPTED_TEXT if reason < 0 else FAILED_TEXT, false)


func _on_cast_delayed(caster: int, delay_msec: int) -> void:
	if _is_player(caster) and _mode == Mode.CASTING:
		_start += delay_msec / 1000.0
		_end += delay_msec / 1000.0


func _on_channel_started(spell_id: int, duration_msec: int) -> void:
	_begin(Mode.CHANNELING, spell_id, duration_msec)


func _on_channel_updated(remaining_msec: int) -> void:
	if _mode == Mode.CHANNELING:
		var length: float = _end - _start
		_end = _now() + remaining_msec / 1000.0
		_start = _end - length
