@tool
class_name BindingStress
extends Node

const ROUNDS: int = 4
const CENTER: Vector2i = Vector2i(31, 49)


# A reloadable extension wrapping engine objects on many threads used to corrupt the editor heap.
func _ready() -> void:
	if not Engine.is_editor_hint() or not _launched_with_this_scene():
		return
	var loader: WowLoader = WowAssets.loader
	var tasks: PackedInt64Array = []
	for round: int in ROUNDS:
		for y: int in range(CENTER.y - 1, CENTER.y + 2):
			for x: int in range(CENTER.x - 1, CENTER.x + 2):
				tasks.append(WorkerThreadPool.add_task(loader.load_adt.bind("Azeroth", x, y)))
	for task: int in tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	print("binding stress survived %d threaded tile builds" % tasks.size())
	get_tree().quit()


# Only runs when the editor was started on this scene, so opening it by hand never quits the editor.
func _launched_with_this_scene() -> bool:
	for arg: String in OS.get_cmdline_args():
		if arg.ends_with(scene_file_path.get_file()):
			return true
	return false
