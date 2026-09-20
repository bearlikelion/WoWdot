class_name MirrorTimer
extends Control

# The timers the server can run, in the order SMSG_START_MIRROR_TIMER numbers them.
enum Kind { FATIGUE, BREATH, FEIGNDEATH }

const LABELS: Dictionary[Kind, String] = {
	Kind.FATIGUE: "EXHAUSTION", Kind.BREATH: "BREATH", Kind.FEIGNDEATH: "FEIGNDEATH",
}
# MirrorTimerColors in MirrorTimer.lua.
const COLORS: Dictionary[Kind, Color] = {
	Kind.FATIGUE: Color(1.0, 0.9, 0.0),
	Kind.BREATH: Color(0.0, 0.5, 1.0),
	Kind.FEIGNDEATH: Color(1.0, 0.7, 0.0),
}

var kind: Kind = Kind.BREATH
var _seconds: float = 0.0
var _scale: float = 0.0
var _paused: bool = false


func _ready() -> void:
	hide()


# MirrorTimerFrame_OnUpdate: the bar runs on at its own rate until the server stops it.
func _process(delta: float) -> void:
	if _paused:
		return
	_seconds += _scale * delta
	_bar().value = clampf(_seconds, 0.0, _bar().max_value)


func start(timer: Kind, value_msec: int, max_msec: int, scale: int, paused: bool) -> void:
	kind = timer
	_seconds = value_msec / 1000.0
	_scale = scale / 1000.0
	_paused = paused
	var bar: TextureProgressBar = _bar()
	bar.min_value = 0.0
	bar.max_value = max_msec / 1000.0
	bar.value = _seconds
	bar.tint_progress = COLORS.get(timer, Color.WHITE)
	_text().text = WowStrings.get_text(LABELS.get(timer, ""))
	show()


func pause(paused: bool) -> void:
	_paused = paused


func _bar() -> TextureProgressBar:
	return get_node("%MirrorTimer1StatusBar")


func _text() -> Label:
	return get_node("%MirrorTimer1Text")
