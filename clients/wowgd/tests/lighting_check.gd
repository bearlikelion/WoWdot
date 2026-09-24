class_name LightingCheck
extends Node

# Logs in, faces the sun and saves user://lighting_<view>_<option>_<on|off>.png pairs to compare.
const MAIN: PackedScene = preload("res://game/main.tscn")
# Hours when the sun is low enough to face without the camera arm hitting the ground.
const HOURS: PackedInt32Array = [8, 17]
const SETTLE_SECONDS: float = 1.0
# Volumetric fog reprojects over several frames before it settles.
const SWITCH_SECONDS: float = 1.0

var _main: Main


func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = "192.168.1.251"
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	_main.auto_character = "Mwarf"
	add_child(_main)
	_main.world_ready.connect(_on_world_ready, CONNECT_ONE_SHOT)


func _on_world_ready(world: World) -> void:
	var sun: DirectionalLight3D = world.get_node("Sun")
	var pivot: Node3D = world.player().get_node("CameraPivot")
	var video: VideoSettings = WowAssets.video
	var saved: Dictionary[StringName, bool] = {}
	for option: StringName in VideoSettings.OPTIONS:
		saved[option] = video.get(option)
	video.shadows = true
	for hour: int in HOURS:
		WowClient.clock.override_minute = hour * 60.0
		await get_tree().create_timer(SETTLE_SECONDS).timeout
		pivot.look_at(pivot.global_position + sun.global_basis.z)
		var gain: float = await _compare("%02d" % hour, &"volumetric_fog")
		print("lighting_check %02d:00 volumetric gain %.4f" % [hour, gain])
		assert(gain != 0.0)
	for option: StringName in saved:
		video.set(option, saved[option])
	video.apply()
	print("lighting_check passed")
	get_tree().quit()


# Saves the view without and with an option and returns how much brighter it makes it.
func _compare(view: String, option: StringName) -> float:
	var brightness: Dictionary[bool, float] = {}
	for on: bool in [false, true]:
		WowAssets.video.set(option, on)
		WowAssets.video.apply()
		await get_tree().create_timer(SWITCH_SECONDS).timeout
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png("user://lighting_%s_%s_%s.png" % [view, option, "on" if on else "off"])
		image.resize(1, 1, Image.INTERPOLATE_LANCZOS)
		brightness[on] = image.get_pixel(0, 0).get_luminance()
	return brightness[true] - brightness[false]
