class_name SoundOptionsFrame
extends Control

signal close_requested

# Check button and slider numbers from SoundOptionsFrame.lua.
const CHECK_BUSES: Dictionary[int, WowAudio.Bus] = {
	1: WowAudio.Bus.MASTER,
	2: WowAudio.Bus.AMBIENCE,
	5: WowAudio.Bus.MUSIC,
}
const SLIDER_BUSES: Dictionary[int, WowAudio.Bus] = {
	1: WowAudio.Bus.MASTER,
	2: WowAudio.Bus.EFFECTS,
	3: WowAudio.Bus.MUSIC,
	4: WowAudio.Bus.AMBIENCE,
}
const CHECK_TEXTS: Dictionary[int, String] = {
	1: "ENABLE_ALL_SOUND",
	2: "ENABLE_AMBIENCE",
	4: "ENABLE_ERROR_SPEECH",
	5: "ENABLE_MUSIC",
	6: "ENABLE_SOUND_AT_CHARACTER",
	7: "ENABLE_EMOTE_SOUNDS",
	8: "ENABLE_MUSIC_LOOPING",
}
const SLIDER_TEXTS: Dictionary[int, String] = {
	1: "MASTER_VOLUME",
	2: "SOUND_VOLUME",
	3: "MUSIC_VOLUME",
	4: "AMBIENCE_VOLUME",
}
const VOLUME_STEP: float = 0.1

var _opened_volumes: Dictionary[WowAudio.Bus, float] = {}
var _opened_enabled: Dictionary[WowAudio.Bus, bool] = {}
var _accepted: bool = false


func _ready() -> void:
	for number: int in CHECK_TEXTS:
		var check: WowButton = _check(number)
		var label: Label = check.get_node("SoundOptionsFrameCheckButton%dText" % number)
		label.text = WowStrings.get_text(CHECK_TEXTS[number])
		if CHECK_BUSES.has(number):
			check.pressed.connect(_on_check_pressed.bind(check, CHECK_BUSES[number]))
		else:
			check.disabled = true
	for number: int in SLIDER_TEXTS:
		var slider: HSlider = _slider(number)
		var prefix: String = "SoundOptionsFrameSlider%d" % number
		(slider.get_node(prefix + "Text") as Label).text = WowStrings.get_text(SLIDER_TEXTS[number])
		(slider.get_node(prefix + "Low") as Label).text = WowStrings.get_text("LOW")
		(slider.get_node(prefix + "High") as Label).text = WowStrings.get_text("HIGH")
		slider.max_value = 1.0
		slider.step = VOLUME_STEP
		slider.value_changed.connect(_on_slider_changed.bind(SLIDER_BUSES[number]))
	%SoundOptionsFrameOkay.pressed.connect(_on_okay_pressed)
	%SoundOptionsFrameCancel.pressed.connect(close_requested.emit)
	%SoundOptionsFrameDefaults.pressed.connect(_on_defaults_pressed)
	visibility_changed.connect(_on_visibility_changed)


func _check(number: int) -> WowButton:
	return get_node("%%SoundOptionsFrameCheckButton%d" % number)


func _slider(number: int) -> HSlider:
	return get_node("%%SoundOptionsFrameSlider%d" % number)


func _refresh() -> void:
	var audio: WowAudio = WowAssets.audio
	for number: int in CHECK_BUSES:
		_check(number).checked = audio.is_bus_enabled(CHECK_BUSES[number])
	for number: int in SLIDER_BUSES:
		_slider(number).set_value_no_signal(audio.volume(SLIDER_BUSES[number]))


# Sliders apply as they move, so closing any way but Okay puts the old values back.
func _on_visibility_changed() -> void:
	var audio: WowAudio = WowAssets.audio
	if not is_visible_in_tree():
		if not _accepted:
			for bus: WowAudio.Bus in _opened_volumes:
				audio.set_volume(bus, _opened_volumes[bus])
				audio.set_bus_enabled(bus, _opened_enabled[bus])
		return
	_accepted = false
	for bus: WowAudio.Bus in WowAudio.BUS_NAMES:
		_opened_volumes[bus] = audio.volume(bus)
		_opened_enabled[bus] = audio.is_bus_enabled(bus)
	_refresh()


func _on_check_pressed(check: WowButton, bus: WowAudio.Bus) -> void:
	check.checked = not check.checked
	WowAssets.audio.set_bus_enabled(bus, check.checked)


func _on_slider_changed(value: float, bus: WowAudio.Bus) -> void:
	WowAssets.audio.set_volume(bus, value)


func _on_okay_pressed() -> void:
	_accepted = true
	WowAssets.audio.save_settings()
	close_requested.emit()


func _on_defaults_pressed() -> void:
	var audio: WowAudio = WowAssets.audio
	for bus: WowAudio.Bus in WowAudio.BUS_NAMES:
		audio.set_volume(bus, 1.0)
		audio.set_bus_enabled(bus, true)
	_refresh()
