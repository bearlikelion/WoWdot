@tool
class_name EditorFocusCheck
extends Node3D

const SETTLE_FRAMES: int = 240
const NEAR: float = 600.0


# Opened in the editor, this checks that picking a map flies the editor camera onto its content.
func _ready() -> void:
	if not Engine.is_editor_hint() or not _launched_with_this_scene():
		return
	var map: WowMap = $WowMap
	var editor: Object = Engine.get_singleton("EditorInterface")
	var camera: Camera3D = editor.get_editor_viewport_3d(0).get_camera_3d()
	var failures: int = 0
	var tree: SceneTree = get_tree()
	for map_name: String in ["test", "Shadowfang"]:
		map.map_name = map_name
		for i: int in SETTLE_FRAMES:
			await tree.process_frame
		var focus: Vector3 = map.get_node("Focus").global_position
		var distance: float = camera.global_position.distance_to(focus)
		var ok: bool = distance < NEAR
		failures += 0 if ok else 1
		print("%s: camera %.0f from focus at wow %s, %d tiles loaded %s" % [
			map_name, distance, WowCoords.from_godot(focus).round(),
			map.loaded_tiles().size(), "OK" if ok else "FAIL",
		])
	print("editor_focus: ", "OK" if failures == 0 else "%d failed" % failures)
	get_tree().quit()


# Only runs when the editor was started on this scene, so opening it by hand never quits the editor.
func _launched_with_this_scene() -> bool:
	for arg: String in OS.get_cmdline_args():
		if arg.ends_with(scene_file_path.get_file()):
			return true
	return false
