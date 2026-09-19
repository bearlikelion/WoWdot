class_name WowAudio
extends Node

enum Bus { MASTER, MUSIC, AMBIENCE, EFFECTS }
enum AreaColumn { PARENT = 2, AMBIENCE = 7, ZONE_MUSIC = 8 }
enum AmbienceColumn { DAY = 1, NIGHT = 2 }
enum ZoneMusicColumn { SILENCE_MIN_DAY = 2, SILENCE_MIN_NIGHT = 3, DAY = 6, NIGHT = 7 }
enum SoundColumn { NAME = 2, FIRST_FILE = 3, LAST_FILE = 12, DIRECTORY = 23, VOLUME = 24 }

# Kept apart from Glue's settings.cfg, which Glue rewrites from its own copy.
const SETTINGS_PATH: String = "user://sound.cfg"
const SETTINGS_SECTION: String = "sound"
const UI_SOUNDS_PATH: String = "res://data/classic/ui_sounds.json"
const BUS_NAMES: Dictionary[Bus, StringName] = {
	Bus.MASTER: &"Master",
	Bus.MUSIC: &"Music",
	Bus.AMBIENCE: &"Ambience",
	Bus.EFFECTS: &"Effects",
}
const DAY_START_HOUR: int = 6
const NIGHT_START_HOUR: int = 18
const FADE_SECONDS: float = 2.0
const SILENT_DB: float = -60.0
const SHOWN_META: StringName = &"audio_shown"

var _areas: WowDBC
var _zone_music: WowDBC
var _ambience: WowDBC
var _sounds: WowDBC
var _sound_rows: Dictionary[String, int] = {}
var _streams: Dictionary[String, AudioStream] = {}
var _ui_sounds: Dictionary = {}
var _settings: ConfigFile = ConfigFile.new()
var _music_path: String = ""
var _zone_music_id: int = 0
var _ambience_id: int = 0
var _fade: Tween

@onready var _music: AudioStreamPlayer = %Music
@onready var _ambient: AudioStreamPlayer = %Ambience
@onready var _effects: AudioStreamPlayer = %Effects
@onready var _silence: Timer = %Silence


func _ready() -> void:
	var archive: WowArchive = WowAssets.archive
	_areas = WowDBC.open(archive, "AreaTable")
	_zone_music = WowDBC.open(archive, "ZoneMusic")
	_ambience = WowDBC.open(archive, "SoundAmbience")
	_sounds = WowDBC.open(archive, "SoundEntries")
	for row: int in _sounds.row_count():
		_sound_rows[_sounds.get_string(row, SoundColumn.NAME).to_lower()] = row
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string(UI_SOUNDS_PATH))
	if table is Dictionary:
		_ui_sounds = table
	_settings.load(SETTINGS_PATH)
	for bus: Bus in BUS_NAMES:
		_apply(bus)
	_music.finished.connect(_on_music_finished)
	_ambient.finished.connect(_ambient.play)
	_silence.timeout.connect(_play_zone_track)
	get_tree().node_added.connect(_on_node_added)


func play_music(path: String) -> void:
	_zone_music_id = 0
	_silence.stop()
	if path == _music_path and _music.playing:
		return
	_start_music(path, 1.0)


func stop_music() -> void:
	_zone_music_id = 0
	_silence.stop()
	_start_music("", 0.0)


func stop_ambience() -> void:
	_ambience_id = 0
	_ambient.stop()


# Subzones usually have no music or ambience of their own, so the owning zone's plays.
func play_zone(area_id: int) -> void:
	var music_id: int = _area_value(area_id, AreaColumn.ZONE_MUSIC)
	if music_id != _zone_music_id:
		_zone_music_id = music_id
		_silence.stop()
		_play_zone_track()
	var ambience_id: int = _area_value(area_id, AreaColumn.AMBIENCE)
	if ambience_id == _ambience_id:
		return
	_ambience_id = ambience_id
	var column: AmbienceColumn = AmbienceColumn.NIGHT if _is_night() else AmbienceColumn.DAY
	var sound_id: int = _ambience.get_uint(_ambience.find(ambience_id), column)
	_ambient.stream = entry_stream(sound_id)
	_ambient.volume_linear = entry_volume(sound_id)
	if _ambient.stream:
		_ambient.play()
	else:
		_ambient.stop()


# Takes a SoundEntries name, as FrameXML's PlaySound does.
func play_sound(sound_name: String) -> void:
	var row: int = _sound_rows.get(sound_name.to_lower(), -1)
	var stream: AudioStream = _load(_random_file(row))
	if stream == null:
		return
	if not _effects.playing:
		_effects.play()
	var playback: AudioStreamPlaybackPolyphonic = _effects.get_stream_playback()
	playback.play_stream(
		stream, 0.0, linear_to_db(_sounds.get_float(row, SoundColumn.VOLUME))
	)


# A random one of the SoundEntries row's files.
func entry_stream(sound_id: int) -> AudioStream:
	return _load(_random_file(_sounds.find(sound_id))) if sound_id > 0 else null


func entry_volume(sound_id: int) -> float:
	var row: int = _sounds.find(sound_id)
	return _sounds.get_float(row, SoundColumn.VOLUME) if row >= 0 else 0.0


func volume(bus: Bus) -> float:
	return _settings.get_value(SETTINGS_SECTION, "%s_volume" % BUS_NAMES[bus], 1.0)


func is_bus_enabled(bus: Bus) -> bool:
	return _settings.get_value(SETTINGS_SECTION, "%s_enabled" % BUS_NAMES[bus], true)


func set_volume(bus: Bus, linear: float) -> void:
	_settings.set_value(SETTINGS_SECTION, "%s_volume" % BUS_NAMES[bus], clampf(linear, 0.0, 1.0))
	_apply(bus)


func set_bus_enabled(bus: Bus, enabled: bool) -> void:
	_settings.set_value(SETTINGS_SECTION, "%s_enabled" % BUS_NAMES[bus], enabled)
	_apply(bus)


func save_settings() -> void:
	_settings.save(SETTINGS_PATH)


func _apply(bus: Bus) -> void:
	var index: int = AudioServer.get_bus_index(BUS_NAMES[bus])
	AudioServer.set_bus_volume_linear(index, volume(bus))
	AudioServer.set_bus_mute(index, not is_bus_enabled(bus))


func _area_value(area_id: int, column: AreaColumn) -> int:
	var found: int = 0
	var row: int = _areas.find(area_id)
	while row >= 0 and found == 0:
		found = _areas.get_uint(row, column)
		var parent: int = _areas.get_uint(row, AreaColumn.PARENT)
		row = _areas.find(parent) if parent != 0 else -1
	return found


# ponytail: day and night follow the local clock, switch to SMSG_LOGIN_SETTIMESPEED game time.
func _is_night() -> bool:
	var hour: int = Time.get_time_dict_from_system()["hour"]
	return hour < DAY_START_HOUR or hour >= NIGHT_START_HOUR


func _play_zone_track() -> void:
	var row: int = _zone_music.find(_zone_music_id)
	var column: ZoneMusicColumn = ZoneMusicColumn.NIGHT if _is_night() else ZoneMusicColumn.DAY
	var sound_id: int = _zone_music.get_uint(row, column) if row >= 0 else 0
	_start_music(_random_file(_sounds.find(sound_id)), entry_volume(sound_id))


# Fades out whatever plays, then starts the new track; an empty path only fades out.
func _start_music(path: String, linear: float) -> void:
	_music_path = path
	if _fade:
		_fade.kill()
	_fade = create_tween()
	if _music.playing:
		_fade.tween_property(_music, "volume_db", SILENT_DB, FADE_SECONDS)
	_fade.tween_callback(_switch_music.bind(_load(path), linear))


func _switch_music(stream: AudioStream, linear: float) -> void:
	_music.stop()
	_music.stream = stream
	_music.volume_linear = linear
	if stream:
		_music.play()


func _random_file(sound_row: int) -> String:
	if sound_row < 0:
		return ""
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
	if path.is_empty():
		return null
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


# Deferred so a frame that hides itself in _ready makes no sound.
func _on_node_added(node: Node) -> void:
	if _ui_sounds.has(String(node.name)):
		_hook.call_deferred(node, _ui_sounds[String(node.name)])


func _hook(node: Node, sounds: Dictionary) -> void:
	if not is_instance_valid(node):
		return
	var button: BaseButton = node as BaseButton
	if button and sounds.has("click"):
		button.pressed.connect(play_sound.bind(sounds["click"]))
	var item: CanvasItem = node as CanvasItem
	if item and (sounds.has("show") or sounds.has("hide")):
		item.set_meta(SHOWN_META, item.visible)
		item.visibility_changed.connect(_on_visibility_changed.bind(item, sounds))


func _on_visibility_changed(item: CanvasItem, sounds: Dictionary) -> void:
	if item.visible == item.get_meta(SHOWN_META):
		return
	item.set_meta(SHOWN_META, item.visible)
	var parent: CanvasItem = item.get_parent() as CanvasItem
	if parent == null or parent.is_visible_in_tree():
		play_sound(sounds.get("show" if item.visible else "hide", ""))
