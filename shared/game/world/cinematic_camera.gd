class_name CinematicCamera
extends Camera3D

signal finished

# CinematicSequences.dbc names the camera; CinematicCamera.dbc holds its model, origin and facing.
const SEQUENCE_CAMERA_COLUMN: int = 2
const MODEL_COLUMN: int = 1
const ORIGIN_COLUMNS: PackedInt32Array = [3, 4, 5]
const FACING_COLUMN: int = 6

var _eye: Array = []
var _look: Array = []
var _elapsed_msec: int = 0
var _length_msec: int = 0
var _origin: Vector3 = Vector3.ZERO
var _facing: float = 0.0


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_elapsed_msec += int(delta * 1000.0)
	var eye: Vector3 = _plant(_sample(_eye, _elapsed_msec))
	var look: Vector3 = _plant(_sample(_look, _elapsed_msec))
	global_position = eye
	if not eye.is_equal_approx(look):
		look_at(look)
	if _elapsed_msec >= _length_msec:
		stop()


func _unhandled_input(event: InputEvent) -> void:
	if current and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		stop()


# False when the sequence names no camera model this client can read.
func play(sequence_id: int) -> bool:
	var sequences: WowDBC = WowDBC.open(WowAssets.archive, "CinematicSequences")
	var cameras: WowDBC = WowDBC.open(WowAssets.archive, "CinematicCamera")
	var row: int = sequences.find(sequence_id)
	if row < 0:
		return false
	var camera_row: int = cameras.find(sequences.get_uint(row, SEQUENCE_CAMERA_COLUMN))
	if camera_row < 0:
		return false
	var path: String = cameras.get_string(camera_row, MODEL_COLUMN).replace(".mdx", ".m2")
	var info: Dictionary = WowAssets.loader.get_m2_info(path)
	var shots: Array = info.get("cameras", [])
	if shots.is_empty():
		return false
	var shot: Dictionary = shots[0]
	_eye = shot["position_keys"]
	_look = shot["target_keys"]
	if _eye.is_empty():
		return false
	fov = rad_to_deg(shot["fov"])
	_origin = Vector3(
		cameras.get_float(camera_row, ORIGIN_COLUMNS[0]),
		cameras.get_float(camera_row, ORIGIN_COLUMNS[1]),
		cameras.get_float(camera_row, ORIGIN_COLUMNS[2]),
	)
	_facing = cameras.get_float(camera_row, FACING_COLUMN)
	_length_msec = maxi(_eye[-1]["msec"], _look[-1]["msec"] if not _look.is_empty() else 0)
	_elapsed_msec = 0
	_process(0.0)
	make_current()
	set_process(true)
	return true


func stop() -> void:
	if not is_processing():
		return
	set_process(false)
	finished.emit()


# The model's frame turns by the facing about WoW's up axis before it lands on the origin.
func _plant(local: Vector3) -> Vector3:
	var wow: Vector3 = WowCoords.from_godot(local)
	var turned: Vector3 = Vector3(
		wow.x * cos(_facing) - wow.y * sin(_facing),
		wow.x * sin(_facing) + wow.y * cos(_facing),
		wow.z,
	)
	return WowCoords.to_godot(_origin + turned)


static func _sample(keys: Array, msec: int) -> Vector3:
	if keys.is_empty():
		return Vector3.ZERO
	for i: int in range(1, keys.size()):
		if msec < keys[i]["msec"]:
			var span: float = float(keys[i]["msec"] - keys[i - 1]["msec"])
			var t: float = (msec - keys[i - 1]["msec"]) / maxf(span, 1.0)
			return keys[i - 1]["point"].lerp(keys[i]["point"], t)
	return keys[-1]["point"]
