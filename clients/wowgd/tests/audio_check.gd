class_name AudioCheck
extends Node

const COLDRIDGE_VALLEY: int = 132
const FIREBALL: int = 133
const HUMAN_MALE_DISPLAY: int = 49
const PANELS: PackedScene = preload("res://ui/ui_panels.tscn")


# Run with `--headless tests/audio_check.tscn`; needs no server.
func _ready() -> void:
	var audio: WowAudio = WowAssets.audio
	var music: AudioStreamPlayer = audio.get_node("%Music")
	var ambience: AudioStreamPlayer = audio.get_node("%Ambience")
	var effects: AudioStreamPlayer = audio.get_node("%Effects")
	audio.play_music(Glue.MUSIC)
	await audio._fade.finished
	assert(music.playing and music.stream.get_length() > 60.0)
	audio.play_zone(COLDRIDGE_VALLEY)
	assert(ambience.playing)
	await audio._fade.finished
	assert(music.playing and "Mountain" in audio._music_path)
	audio.play_sound("igMainMenuOpen")
	assert(effects.playing)
	for sound_name: String in [
		LootFrame.COIN_SOUND, LootFrame.ITEM_SOUND, MerchantFrame.COIN_SOUND,
	]:
		assert(audio._sound_rows.has(sound_name.to_lower()), "unknown sound " + sound_name)

	var camera: Camera3D = Camera3D.new()
	add_child(camera)
	var model: Node3D = Node3D.new()
	add_child(model)
	UnitVoice.attach(model, 1, HUMAN_MALE_DISPLAY)
	var voice: UnitVoice = UnitVoice.by_guid[1]
	assert(voice._sound_row >= 0 and voice._footstep_id > 0)
	voice.play_sound(UnitVoice.Sound.ATTACK)
	assert(voice.playing)
	assert(UnitVoice._kit_sound(FIREBALL, UnitVoice.Kit.PRECAST) > 0)
	assert(UnitVoice._kit_sound(FIREBALL, UnitVoice.Kit.IMPACT) > 0)
	UnitVoice.set_gait(model, "Run")
	assert(not voice._steps.is_stopped())

	var panels: PanelManager = PANELS.instantiate()
	add_child(panels)
	var options: SoundOptionsFrame = panels.get_node("%SoundOptionsFrame")
	panels.show_panel(options)
	var slider: HSlider = options.get_node("%SoundOptionsFrameSlider3")
	slider.value = 0.5
	var bus: int = AudioServer.get_bus_index(&"Music")
	assert(is_equal_approx(AudioServer.get_bus_volume_linear(bus), 0.5))
	panels.hide_panel(options)
	assert(is_equal_approx(AudioServer.get_bus_volume_linear(bus), audio.volume(WowAudio.Bus.MUSIC)))
	assert(not is_equal_approx(audio.volume(WowAudio.Bus.MUSIC), 0.5))
	print("audio_check passed")
	get_tree().quit()
