class_name MapView
extends Node3D

const SETTLE_FRAMES: int = 30
const LOAD_TIMEOUT_MS: int = 120000

@onready var _map: WowMap = $WowMap
@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	var args: Dictionary = _parse_args()
	_camera.position = WowCoords.to_godot(_vec3(args.get("pos", "-9380,-20,130")))
	_camera.look_at(WowCoords.to_godot(_vec3(args.get("look", "-9464,62,56"))))
	_map.map_name = args.get("map", "Azeroth")
	var started: int = Time.get_ticks_msec()
	await _wait_for_tiles()
	print("tiles %s loaded in %d ms" % [_map.loaded_tiles(), Time.get_ticks_msec() - started])
	if args.has("fly_to"):
		await _fly(_vec3(args["fly_to"]), float(args.get("fly_time", "20")))
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	var out: String = args.get("out", "user://map_view.png")
	get_viewport().get_texture().get_image().save_png(out)
	print("wrote ", ProjectSettings.globalize_path(out))
	get_tree().quit()


func _wait_for_tiles() -> void:
	var deadline: int = Time.get_ticks_msec() + LOAD_TIMEOUT_MS
	await get_tree().process_frame
	await get_tree().process_frame
	while not _map.is_idle() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


# Reports main-thread frame times while tiles stream in the background.
func _fly(destination: Vector3, seconds: float) -> void:
	var start: Vector3 = _camera.position
	var end: Vector3 = WowCoords.to_godot(destination)
	var frame_ms: PackedFloat32Array = []
	var elapsed: float = 0.0
	var last: int = Time.get_ticks_usec()
	while elapsed < seconds:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		last = now
		elapsed += get_process_delta_time()
		_camera.position = start.lerp(end, clampf(elapsed / seconds, 0.0, 1.0))
	await _wait_for_tiles()
	frame_ms.sort()
	print("fly: %d frames, median %.1f ms, p99 %.1f ms, worst %.1f ms" % [
		frame_ms.size(),
		frame_ms[frame_ms.size() / 2],
		frame_ms[int(frame_ms.size() * 0.99)],
		frame_ms[frame_ms.size() - 1],
	])


func _parse_args() -> Dictionary:
	var args: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	return args


func _vec3(text: String) -> Vector3:
	var parts: PackedFloat64Array = text.split_floats(",")
	return Vector3(parts[0], parts[1], parts[2])
