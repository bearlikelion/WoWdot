class_name UnitVoice
extends AudioStreamPlayer3D

# CreatureSoundData columns.
enum Sound { ATTACK = 1, ATTACK_CRITICAL = 2, WOUND = 3, WOUND_CRITICAL = 4, DEATH = 6, AGGRO = 10 }
# NPCSounds columns.
enum Speech { GREETING = 1, FAREWELL = 2, PISSED = 3 }
# WeaponImpactSounds columns; the critical variant sits CRITICAL_OFFSET columns later.
enum Impact { FLESH = 3, BLOCK = 6, PARRY = 8 }
# SpellVisual columns.
enum Kit { PRECAST = 1, CAST = 2, IMPACT = 3 }
enum VictimState { HIT = 1, PARRY = 3, BLOCK = 5 }
# WeaponSwingSounds2 rows.
enum Swing { LIGHT = 1, LIGHT_CRITICAL = 2 }
# FootstepTerrainLookup columns.
enum Step { CREATURE = 1, TERRAIN = 2, SOUND = 3, SPLASH = 4 }
# TerrainType rows, which GroundEffectTexture names for each ground texture.
enum Terrain { DIRT, METALLIC, STONE, SNOW, WOOD, GRASS, LEAVES, SAND, SOGGY, DUSTY_GRASS, NONE }

const SCENE_PATH: String = "res://game/world/unit_voice.tscn"
const NODE_NAME: StringName = &"UnitVoice"
const CRITICAL_OFFSET: int = 10
const HIT_INFO_CRITICAL: int = 0x80
const MAIN_HAND_SLOT: int = 15
const ITEM_CLASS_WEAPON: int = 2
const FIST_WEAPON: int = 13
const DISPLAY_SOUND_COLUMN: int = 2
const DISPLAY_MODEL_COLUMN: int = 1
const DISPLAY_NPC_SOUND_COLUMN: int = 11
const MODEL_SOUND_COLUMN: int = 13
const FOOTSTEP_COLUMN: int = 9
const SPELL_VISUAL_COLUMN: int = 115
const KIT_SOUND_COLUMN: int = 13
const SWING_SOUND_COLUMN: int = 3
const GROUND_TERRAIN_COLUMN: int = 6
# ponytail: a fixed stride per gait, the M2 footstep events would give the exact frames.
const STRIDES: Dictionary[String, float] = {
	"Run": 0.33,
	"Walk": 0.55,
	"Walkbackwards": 0.55,
	"ShuffleLeft": 0.4,
	"ShuffleRight": 0.4,
}

static var by_guid: Dictionary[int, UnitVoice] = {}
## Where footsteps leave their prints, when a world provides one.
static var footprints: Footprints
## The terrain a unit walks on decides its footstep sound; unset, every step lands on dirt.
static var map: WowMap
## Sounds past max_distance from this are skipped; unset, the camera stands in.
static var listener: Node3D

static var _displays: WowDBC
static var _models: WowDBC
static var _creature_sounds: WowDBC
static var _npc_sounds: WowDBC
static var _spells: WowDBC
static var _visuals: WowDBC
static var _kits: WowDBC
static var _swings: WowDBC
# Keyed by (CreatureSoundData footstep id, Terrain).
static var _footsteps: Dictionary[Vector2i, int] = {}
static var _splashes: Dictionary[Vector2i, int] = {}
static var _ground_terrain: Dictionary[int, Terrain] = {}
static var _impacts: Dictionary[int, int] = {}
static var _impact_table: WowDBC

var _guid: int = 0
var _sound_row: int = -1
var _npc_row: int = -1
var _footstep_id: int = 0
var _model_id: int = 0
var _was_alive: bool = false
var _precast: int = AudioStreamPlaybackPolyphonic.INVALID_ID

@onready var _steps: Timer = %Steps


func _ready() -> void:
	_steps.timeout.connect(_on_step)


func _exit_tree() -> void:
	if by_guid.get(_guid) == self:
		by_guid.erase(_guid)


# The mount's display, when riding, gives the footsteps.
static func attach(model: Node3D, guid: int, display_id: int, mount_display_id: int = 0) -> void:
	if _displays == null:
		_open()
	var voice: UnitVoice = (load(SCENE_PATH) as PackedScene).instantiate()
	voice.name = NODE_NAME
	voice._guid = guid
	voice._sound_row = _sound_data_row(display_id)
	voice._npc_row = _npc_sounds.find(
		_displays.get_uint(_displays.find(display_id), DISPLAY_NPC_SOUND_COLUMN)
	)
	var walker: int = _sound_data_row(mount_display_id) if mount_display_id else voice._sound_row
	var display: int = _displays.find(mount_display_id if mount_display_id else display_id)
	voice._model_id = _displays.get_uint(display, DISPLAY_MODEL_COLUMN) if display >= 0 else 0
	if walker >= 0:
		voice._footstep_id = _creature_sounds.get_uint(walker, FOOTSTEP_COLUMN)
	model.add_child(voice)
	by_guid[guid] = voice


static func set_gait(model: Node3D, clip: String) -> void:
	var voice: UnitVoice = model.get_node_or_null(NodePath(NODE_NAME)) as UnitVoice
	if voice == null:
		return
	var stride: float = STRIDES.get(clip, 0.0)
	if stride <= 0.0:
		voice._steps.stop()
	elif voice._steps.is_stopped() or not is_equal_approx(voice._steps.wait_time, stride):
		voice._steps.start(stride)


static func speak(guid: int, speech: Speech) -> void:
	var voice: UnitVoice = by_guid.get(guid)
	if voice and voice._npc_row >= 0:
		voice.play_entry(_npc_sounds.get_uint(voice._npc_row, speech))


func play_sound(sound: Sound) -> void:
	if _sound_row >= 0:
		play_entry(_creature_sounds.get_uint(_sound_row, sound))


# Returns the polyphonic stream id, for stopping a looping sound early.
func play_entry(sound_id: int) -> int:
	var ear: Node3D = listener if is_instance_valid(listener) else get_viewport().get_camera_3d()
	if sound_id <= 0 or ear == null \
	or ear.global_position.distance_to(global_position) > max_distance:
		return AudioStreamPlaybackPolyphonic.INVALID_ID
	var audio: WowAudio = WowAssets.audio
	var sound: AudioStream = audio.entry_stream(sound_id)
	if sound == null:
		return AudioStreamPlaybackPolyphonic.INVALID_ID
	if not playing:
		play()
	var playback: AudioStreamPlaybackPolyphonic = get_stream_playback()
	return playback.play_stream(sound, 0.0, linear_to_db(audio.entry_volume(sound_id)))


static func _open() -> void:
	var archive: WowArchive = WowAssets.archive
	_displays = WowDBC.open(archive, "CreatureDisplayInfo")
	_models = WowDBC.open(archive, "CreatureModelData")
	_creature_sounds = WowDBC.open(archive, "CreatureSoundData")
	_npc_sounds = WowDBC.open(archive, "NPCSounds")
	_spells = WowDBC.open(archive, "Spell")
	_visuals = WowDBC.open(archive, "SpellVisual")
	_kits = WowDBC.open(archive, "SpellVisualKit")
	_swings = WowDBC.open(archive, "WeaponSwingSounds2")
	_impact_table = WowDBC.open(archive, "WeaponImpactSounds")
	for row: int in _impact_table.row_count():
		_impacts[_impact_table.get_uint(row, 1)] = row
	var lookup: WowDBC = WowDBC.open(archive, "FootstepTerrainLookup")
	for row: int in lookup.row_count():
		# The lookup counts terrain from one, TerrainType and GroundEffectTexture from zero.
		var key: Vector2i = Vector2i(
			lookup.get_uint(row, Step.CREATURE), lookup.get_uint(row, Step.TERRAIN) - 1
		)
		_footsteps[key] = lookup.get_uint(row, Step.SOUND)
		_splashes[key] = lookup.get_uint(row, Step.SPLASH)
	var ground: WowDBC = WowDBC.open(archive, "GroundEffectTexture")
	for row: int in ground.row_count():
		var terrain: int = ground.get_uint(row, GROUND_TERRAIN_COLUMN)
		if terrain > 0:
			_ground_terrain[ground.get_uint(row, 0)] = terrain as Terrain
	var session: WowSession = WowClient.session
	session.melee_swing.connect(_on_melee_swing)
	session.attack_started.connect(_on_attack_started)
	session.object_updated.connect(_on_object_updated)
	session.spell_cast_started.connect(_on_spell_cast_started)
	session.spell_cast_finished.connect(_on_spell_cast_finished)
	session.spell_cast_failed.connect(_on_spell_cast_failed)


# Player races keep their sounds on the model, creatures on the display.
static func _sound_data_row(display_id: int) -> int:
	var display: int = _displays.find(display_id)
	if display < 0:
		return -1
	var sound_id: int = _displays.get_uint(display, DISPLAY_SOUND_COLUMN)
	if sound_id == 0:
		var model: int = _models.find(_displays.get_uint(display, DISPLAY_MODEL_COLUMN))
		sound_id = _models.get_uint(model, MODEL_SOUND_COLUMN) if model >= 0 else 0
	return _creature_sounds.find(sound_id) if sound_id else -1


static func _weapon_subclass(guid: int) -> int:
	var session: WowSession = WowClient.session
	if session.get_object_type(guid) != Entities.ObjectType.PLAYER:
		return FIST_WEAPON
	var entry: int = CharacterModels.visible_items(session, guid)[MAIN_HAND_SLOT]
	var info: Dictionary = session.get_item_info(entry) if entry else {}
	if info.get("class", -1) != ITEM_CLASS_WEAPON:
		return FIST_WEAPON
	return info.get("subclass", FIST_WEAPON)


static func _on_melee_swing(
	attacker: int, victim: int, damage: int, hit_info: int, victim_state: int,
) -> void:
	var critical: bool = (hit_info & HIT_INFO_CRITICAL) != 0
	var swinger: UnitVoice = by_guid.get(attacker)
	var struck: UnitVoice = by_guid.get(victim)
	if swinger:
		swinger.play_sound(Sound.ATTACK_CRITICAL if critical else Sound.ATTACK)
	var impact: int = -1
	match victim_state:
		VictimState.HIT when damage > 0:
			impact = Impact.FLESH
		VictimState.PARRY:
			impact = Impact.PARRY
		VictimState.BLOCK:
			impact = Impact.BLOCK
	if impact < 0:
		if swinger:
			var swing: int = _swings.find(Swing.LIGHT_CRITICAL if critical else Swing.LIGHT)
			swinger.play_entry(_swings.get_uint(swing, SWING_SOUND_COLUMN))
		return
	if struck == null:
		return
	var row: int = _impacts.get(_weapon_subclass(attacker), _impacts.get(FIST_WEAPON, 0))
	struck.play_entry(_impact_table.get_uint(row, impact + (CRITICAL_OFFSET if critical else 0)))
	if impact == Impact.FLESH:
		struck.play_sound(Sound.WOUND_CRITICAL if critical else Sound.WOUND)


static func _on_attack_started(attacker: int, _victim: int) -> void:
	var voice: UnitVoice = by_guid.get(attacker)
	if voice and WowClient.session.get_object_type(attacker) == Entities.ObjectType.UNIT:
		voice.play_sound(Sound.AGGRO)


static func _on_object_updated(guid: int) -> void:
	var voice: UnitVoice = by_guid.get(guid)
	if voice == null:
		return
	var alive: bool = WowClient.session.get_field(guid, "UNIT_FIELD_HEALTH") > 0
	if voice._was_alive and not alive:
		voice.play_sound(Sound.DEATH)
	voice._was_alive = alive


static func _kit_sound(spell_id: int, kit: Kit) -> int:
	var spell: int = _spells.find(spell_id)
	if spell < 0:
		return 0
	var visual: int = _visuals.find(_spells.get_uint(spell, SPELL_VISUAL_COLUMN))
	var row: int = _kits.find(_visuals.get_uint(visual, kit)) if visual >= 0 else -1
	return _kits.get_uint(row, KIT_SOUND_COLUMN) if row >= 0 else 0


static func _on_spell_cast_started(caster: int, spell_id: int, _cast_time_msec: int) -> void:
	var voice: UnitVoice = by_guid.get(caster)
	if voice:
		voice._stop_precast()
		voice._precast = voice.play_entry(_kit_sound(spell_id, Kit.PRECAST))


# The impact sounds at each target it lands on, or at the caster of a targetless spell.
static func _on_spell_cast_finished(
	caster: int, spell_id: int, targets: PackedInt64Array,
) -> void:
	var voice: UnitVoice = by_guid.get(caster)
	if voice:
		voice._stop_precast()
		voice.play_entry(_kit_sound(spell_id, Kit.CAST))
	var impact: int = _kit_sound(spell_id, Kit.IMPACT)
	var struck: bool = false
	for target: int in targets:
		var hit: UnitVoice = by_guid.get(target)
		if hit:
			hit.play_entry(impact)
			struck = true
	if voice and not struck:
		voice.play_entry(impact)


static func _on_spell_cast_failed(caster: int, _spell_id: int, _reason: int) -> void:
	var voice: UnitVoice = by_guid.get(caster)
	if voice:
		voice._stop_precast()


func _stop_precast() -> void:
	if _precast != AudioStreamPlaybackPolyphonic.INVALID_ID and playing:
		(get_stream_playback() as AudioStreamPlaybackPolyphonic).stop_stream(_precast)
	_precast = AudioStreamPlaybackPolyphonic.INVALID_ID


func _on_step() -> void:
	var key: Vector2i = Vector2i(_footstep_id, _terrain_under())
	var wading: bool = map != null and global_position.y < map.liquid_height_at(global_position)
	play_entry(_splashes.get(key, 0) if wading else _footsteps.get(key, 0))
	if footprints and not wading and _model_id != 0:
		footprints.stamp(_model_id, get_parent().global_position, get_parent().global_rotation.y)


# Ground with no GroundEffectTexture of its own sounds like dirt, as it does in the stock client.
func _terrain_under() -> Terrain:
	if map == null:
		return Terrain.DIRT
	return _ground_terrain.get(map.ground_effect_at(global_position), Terrain.DIRT)
