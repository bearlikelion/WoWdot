class_name WowAudio
extends Node

enum AreaColumn { PARENT = 2, ZONE_MUSIC = 8 }
enum ZoneMusicColumn { SILENCE_MIN_DAY = 2, SILENCE_MIN_NIGHT = 3, DAY = 6, NIGHT = 7 }
enum SoundColumn { NAME = 2, FIRST_FILE = 3, LAST_FILE = 12, DIRECTORY = 23, VOLUME = 24 }

const BUTTON_SOUND: String = "GLUEGENERICBUTTONPRESS"
const DAY_START_HOUR: int = 6
const NIGHT_START_HOUR: int = 18

var _areas: WowDBC
var _zone_music: WowDBC
var _sounds: WowDBC
var _sound_rows: Dictionary[String, int] = {}
var _streams: Dictionary[String, AudioStream] = {}
var _music_path: String = ""
var _zone_music_id: int = 0

@onready var _music: AudioStreamPlayer = %Music
@onready var _effects: AudioStreamPlayer = %Effects
@onready var _silence: Timer = %Silence


func _ready() -> void:
	var archive: WowArchive = WowAssets.archive
	_areas = WowDBC.open(archive, "AreaTable")
	_zone_music = WowDBC.open(archive, "ZoneMusic")
	_sounds = WowDBC.open(archive, "SoundEntries")
	for row: int in _sounds.row_count():
		_sound_rows[_sounds.get_string(row, SoundColumn.NAME).to_lower()] = row
	_music.finished.connect(_on_music_finished)
	_silence.timeout.connect(_play_zone_track)
	get_tree().node_added.connect(_on_node_added)


func play_music(path: String) -> void:
	_zone_music_id = 0
	_silence.stop()
	if path == _music_path and _music.playing:
		return
	_music_path = path
	_music.stream = _load(path)
	_music.volume_linear = 1.0
	_music.play()


func stop_music() -> void:
	_zone_music_id = 0
	_music_path = ""
	_silence.stop()
	_music.stop()


# Subzones usually have no music of their own, so the owning zone's plays.
func play_zone_music(area_id: int) -> void:
	var music_id: int = 0
	var row: int = _areas.find(area_id)
	while row >= 0 and music_id == 0:
		music_id = _areas.get_uint(row, AreaColumn.ZONE_MUSIC)
		var parent: int = _areas.get_uint(row, AreaColumn.PARENT)
		row = _areas.find(parent) if parent != 0 else -1
	if music_id == _zone_music_id:
		return
	stop_music()
	_zone_music_id = music_id
	_play_zone_track()


# Takes a SoundEntries name, as FrameXML's PlaySound does.
func play_sound(sound_name: String) -> void:
	var row: int = _sound_rows.get(sound_name.to_lower(), -1)
	if row < 0:
		return
	var stream: AudioStream = _load(_random_file(row))
	if stream == null:
		return
	if not _effects.playing:
		_effects.play()
	var playback: AudioStreamPlaybackPolyphonic = _effects.get_stream_playback()
	playback.play_stream(
		stream, 0.0, linear_to_db(_sounds.get_float(row, SoundColumn.VOLUME))
	)


# ponytail: day and night follow the local clock, switch to SMSG_LOGIN_SETTIMESPEED game time.
func _is_night() -> bool:
	var hour: int = Time.get_time_dict_from_system()["hour"]
	return hour < DAY_START_HOUR or hour >= NIGHT_START_HOUR


func _play_zone_track() -> void:
	var row: int = _zone_music.find(_zone_music_id)
	if row < 0:
		return
	var column: ZoneMusicColumn = ZoneMusicColumn.NIGHT if _is_night() else ZoneMusicColumn.DAY
	var sound_row: int = _sounds.find(_zone_music.get_uint(row, column))
	if sound_row < 0:
		return
	_music_path = _random_file(sound_row)
	_music.stream = _load(_music_path)
	_music.volume_linear = _sounds.get_float(sound_row, SoundColumn.VOLUME)
	_music.play()


func _random_file(sound_row: int) -> String:
	var files: PackedStringArray = []
	for column: int in range(SoundColumn.FIRST_FILE, SoundColumn.LAST_FILE + 1):
		var file: String = _sounds.get_string(sound_row, column)
		if not file.is_empty():
			files.append(file)
	if files.is_empty():
		return ""
	var directory: String = _sounds.get_string(sound_row, SoundColumn.DIRECTORY)
	return directory + "\\" + files[randi() % files.size()]


func _load(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var stream: AudioStream = null
	var data: PackedByteArray = WowAssets.archive.read(path)
	if not data.is_empty():
		if path.to_lower().ends_with(".mp3"):
			stream = AudioStreamMP3.load_from_buffer(data)
		else:
			stream = AudioStreamWAV.load_from_buffer(data)
	_streams[path] = stream
	return stream


func _on_music_finished() -> void:
	if _zone_music_id == 0:
		_music.play()
		return
	var row: int = _zone_music.find(_zone_music_id)
	var column: ZoneMusicColumn = ZoneMusicColumn.SILENCE_MIN_DAY
	if _is_night():
		column = ZoneMusicColumn.SILENCE_MIN_NIGHT
	_silence.start(maxf(_zone_music.get_uint(row, column) / 1000.0, 1.0))


func _on_node_added(node: Node) -> void:
	var button: BaseButton = node as BaseButton
	if button:
		button.pressed.connect(play_sound.bind(BUTTON_SOUND))
