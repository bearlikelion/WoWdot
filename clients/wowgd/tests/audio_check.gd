class_name AudioCheck
extends Node

const COLDRIDGE_VALLEY: int = 132


# Run with `--headless tests/audio_check.tscn`; needs no server.
func _ready() -> void:
	var audio: WowAudio = WowAssets.audio
	var music: AudioStreamPlayer = audio.get_node("%Music")
	var effects: AudioStreamPlayer = audio.get_node("%Effects")
	audio.play_music(Glue.MUSIC)
	assert(music.playing and music.stream.get_length() > 60.0)
	audio.play_zone_music(COLDRIDGE_VALLEY)
	assert(music.playing and "Mountain" in audio._music_path)
	audio.play_sound("igMainMenuOpen")
	assert(effects.playing)
	audio.stop_music()
	assert(not music.playing)
	print("audio_check passed")
	get_tree().quit()
