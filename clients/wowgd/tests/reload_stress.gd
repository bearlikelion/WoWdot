class_name ReloadStress
extends Node3D

const RELOADS: int = 20


# The editor hot-reloads tool scripts at any time, so reloading mid-stream must not crash.
func _ready() -> void:
	var map: WowMap = $WowMap
	$Camera3D.position = WowCoords.to_godot(Vector3(-9460, 62, 120))
	map.map_name = "Azeroth"
	for i: int in 3:
		await get_tree().process_frame
	for i: int in RELOADS:
		(map.get_script() as GDScript).reload(true)
		await get_tree().process_frame
	while not map.is_idle():
		await get_tree().process_frame
	print("reload repro survived with tiles ", map.loaded_tiles())
	get_tree().quit()
