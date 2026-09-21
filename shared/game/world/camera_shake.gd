class_name CameraShake
extends Node

enum Direction { FORWARD, LEFT, UP }

# CameraShakes.dbc: a one-bit decay switch, an axis, inches, hertz, seconds, a pre-roll and a rate.
const TYPE_COLUMN: int = 1
const DIRECTION_COLUMN: int = 2
const AMPLITUDE_COLUMN: int = 3
const FREQUENCY_COLUMN: int = 4
const DURATION_COLUMN: int = 5
const PHASE_COLUMN: int = 6
const COEFFICIENT_COLUMN: int = 7
const GROUP_SLOTS: int = 3
const DECAYING: int = 1
const INCHES_PER_YARD: float = 36.0
# Full strength inside nine yards, then 0.7 for every nine more, and nothing past eighty.
const NEAR_DISTANCE: float = 9.0
const FALLOFF: float = 0.7
const MAX_DISTANCE: float = 80.0
# CreatureModelData.dbc names the preset a body thumps the camera with as it lands.
const DEATH_THUD_COLUMN: int = 12

@export var player: Player

var _presets: WowDBC
var _groups: WowDBC
var _live: Array[Shake] = []

@onready var _camera: Camera3D = player.get_node("CameraPivot/SpringArm3D/Camera3D")


func _ready() -> void:
	_presets = WowDBC.open(WowAssets.archive, "CameraShakes")
	_groups = WowDBC.open(WowAssets.archive, "SpellEffectCameraShakes")


# ponytail: the forward axis is dropped; the camera's own offsets only move it sideways and up.
func _process(_delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var strongest: Dictionary[Direction, float] = {}
	for shake: Shake in _live.duplicate():
		var t: float = now - shake.started + shake.phase
		if t >= shake.duration:
			_live.erase(shake)
			continue
		var distance: float = _camera.global_position.distance_to(shake.at)
		if distance > MAX_DISTANCE:
			continue
		var amplitude: float = shake.amplitude
		if distance > NEAR_DISTANCE:
			amplitude *= pow(FALLOFF, (distance - NEAR_DISTANCE) / NEAR_DISTANCE)
		var offset: float = amplitude * sin(TAU * shake.frequency * t)
		if shake.decays:
			offset *= exp(-shake.coefficient * t)
		if absf(offset) > absf(strongest.get(shake.direction, 0.0)):
			strongest[shake.direction] = offset
	_camera.h_offset = -strongest.get(Direction.LEFT, 0.0)
	_camera.v_offset = strongest.get(Direction.UP, 0.0)


# A spell visual kit names a group of up to three presets, one for each axis.
func add_group(group_id: int, at: Vector3) -> void:
	var row: int = _groups.find(group_id) if group_id > 0 else -1
	if row < 0:
		return
	for slot: int in GROUP_SLOTS:
		add_preset(_groups.get_uint(row, slot + 1), at)


func add_preset(preset_id: int, at: Vector3) -> void:
	var row: int = _presets.find(preset_id) if preset_id > 0 else -1
	if row < 0:
		return
	var shake: Shake = Shake.new()
	shake.at = at
	shake.started = Time.get_ticks_msec() / 1000.0
	shake.decays = _presets.get_uint(row, TYPE_COLUMN) == DECAYING
	shake.direction = _presets.get_uint(row, DIRECTION_COLUMN) as Direction
	shake.amplitude = _presets.get_float(row, AMPLITUDE_COLUMN) / INCHES_PER_YARD
	shake.frequency = _presets.get_float(row, FREQUENCY_COLUMN)
	shake.duration = _presets.get_float(row, DURATION_COLUMN)
	shake.phase = _presets.get_float(row, PHASE_COLUMN)
	shake.coefficient = _presets.get_float(row, COEFFICIENT_COLUMN)
	_live.append(shake)


class Shake:
	var at: Vector3
	var started: float
	var decays: bool
	var direction: Direction
	var amplitude: float
	var frequency: float
	var duration: float
	var phase: float
	var coefficient: float
