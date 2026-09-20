class_name ModelCheck
extends Node

const HUMAN_MALE: String = "Character\\Human\\Male\\HumanMale.m2"
const RABBIT: String = "Creature\\Rabbit\\Rabbit.m2"
const M2_VERSION: int = 264

var _failures: PackedStringArray = []


func _ready() -> void:
	var loader: WowLoader = WowLoader.get_shared()
	for path: String in [HUMAN_MALE, RABBIT]:
		_check_model(loader, path)
	_finish()


# From version 264 the batches and indices live in a .skin beside the model.
func _check_model(loader: WowLoader, path: String) -> void:
	var info: Dictionary = loader.get_m2_info(path)
	if not _check(not info.is_empty(), "%s reads out of the archives" % path):
		return
	_check(info["version"] == M2_VERSION,
			"%s is version %d" % [path, M2_VERSION])
	_check(not (info["batches"] as Array).is_empty(), "%s names its batches" % path)
	var root: Node3D = loader.load_m2(path)
	if not _check(root != null, "%s builds a node" % path):
		return
	var mesh: MeshInstance3D = root.find_child("Mesh", true, false)
	if not _check(mesh != null and mesh.mesh != null, "%s builds a mesh" % path):
		root.free()
		return
	var surfaces: int = mesh.mesh.get_surface_count()
	var vertices: int = 0
	for surface: int in surfaces:
		vertices += (mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	print("%s: version %d, %d batches, %d surfaces, %d vertices"
			% [path, info["version"], (info["batches"] as Array).size(), surfaces, vertices])
	_check(surfaces > 0 and vertices > 0, "%s has geometry to draw" % path)
	root.free()


func _check(condition: bool, what: String) -> bool:
	if not condition:
		_failures.append(what)
	return condition


func _finish() -> void:
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("model_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
