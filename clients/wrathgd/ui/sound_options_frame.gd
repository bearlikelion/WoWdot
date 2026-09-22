class_name SoundOptionsFrame
extends Control

signal close_requested

# AudioOptionsSoundPanel controls and the global string that names each one.
const CHECK_BUSES: Dictionary[String, WowAudio.Bus] = {
	"EnableSound": WowAudio.Bus.MASTER,
	"SoundEffects": WowAudio.Bus.EFFECTS,
	"Music": WowAudio.Bus.MUSIC,
	"AmbientSounds": WowAudio.Bus.AMBIENCE,
}
const SLIDER_BUSES: Dictionary[String, WowAudio.Bus] = {
	"MasterVolume": WowAudio.Bus.MASTER,
	"SoundVolume": WowAudio.Bus.EFFECTS,
	"MusicVolume": WowAudio.Bus.MUSIC,
	"AmbienceVolume": WowAudio.Bus.AMBIENCE,
}
const CHECK_TEXTS: Dictionary[String, String] = {
	"EnableSound": "ENABLE_SOUND",
	"SoundEffects": "ENABLE_SOUNDFX",
	"ErrorSpeech": "ENABLE_ERROR_SPEECH",
	"EmoteSounds": "ENABLE_EMOTE_SOUNDS",
	"PetSounds": "ENABLE_PET_SOUNDS",
	"Music": "ENABLE_MUSIC",
	"LoopMusic": "ENABLE_MUSIC_LOOPING",
	"AmbientSounds": "ENABLE_AMBIENCE",
	"SoundInBG": "ENABLE_BGSOUND",
	"Reverb": "ENABLE_REVERB",
	"HRTF": "ENABLE_SOFTWARE_HRTF",
	"EnableDSPs": "ENABLE_DSP_EFFECTS",
	"UseHardware": "ENABLE_HARDWARE",
}
const SLIDER_TEXTS: Dictionary[String, String] = {
	"MasterVolume": "MASTER_VOLUME",
	"SoundVolume": "SOUND_VOLUME",
	"MusicVolume": "MUSIC_VOLUME",
	"AmbienceVolume": "AMBIENCE_VOLUME",
}
const VOLUME_STEP: float = 0.1

var _opened_volumes: Dictionary[WowAudio.Bus, float] = {}
var _opened_enabled: Dictionary[WowAudio.Bus, bool] = {}
var _accepted: bool = false


func _ready() -> void:
	for key: String in CHECK_TEXTS:
		var check: WowButton = _control(key)
		_label(key + "Text").text = WowStrings.get_text(CHECK_TEXTS[key])
		if CHECK_BUSES.has(key):
			check.pressed.connect(_on_check_pressed.bind(check, CHECK_BUSES[key]))
		else:
			check.disabled = true
	for key: String in SLIDER_TEXTS:
		var slider: HSlider = _control(key)
		_label(key + "Text").text = WowStrings.get_text(SLIDER_TEXTS[key])
		_label(key + "Low").text = WowStrings.get_text("LOW")
		_label(key + "High").text = WowStrings.get_text("HIGH")
		slider.max_value = 1.0
		slider.step = VOLUME_STEP
		slider.value_changed.connect(_on_slider_changed.bind(SLIDER_BUSES[key]))
	%AudioOptionsFrameOkay.pressed.connect(_on_okay_pressed)
	%AudioOptionsFrameCancel.pressed.connect(close_requested.emit)
	%AudioOptionsFrameDefaults.pressed.connect(_on_defaults_pressed)
	visibility_changed.connect(_on_visibility_changed)


# The converter emits the sound panel twice, so its controls are not unique names.
func _control(key: String) -> Control:
	return %AudioOptionsSoundPanel.find_child("AudioOptionsSoundPanel" + key, true, false)


func _label(key: String) -> Label:
	return _control(key) as Label


func _refresh() -> void:
	var audio: WowAudio = WowAssets.audio
	for key: String in CHECK_BUSES:
		(_control(key) as WowButton).checked = audio.is_bus_enabled(CHECK_BUSES[key])
	for key: String in SLIDER_BUSES:
		(_control(key) as HSlider).set_value_no_signal(audio.volume(SLIDER_BUSES[key]))


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
