class_name TestInstances
extends SceneTree

# Entry points from vMaNGOS areatrigger_teleport, in server coordinates.
const ENTRIES: Dictionary[String, Vector3] = {
	"WailingCaverns": Vector3(-158.4, 131.6, -74.3),
	"Blackfathom": Vector3(-150.2, 106.6, -39.8),
	"GnomeragonInstance": Vector3(-329.1, -3.2, -152.9),
	"BlackRockSpire": Vector3(78.4, -226.8, 49.8),
	"BlackrockDepths": Vector3(456.9, 34.1, -68.1),
	"Mauradon": Vector3(1016.8, -458.5, -43.5),
	"OrgrimmarInstance": Vector3(0.8, -8.2, -15.5),
	"MoltenCore": Vector3(1091.9, -467.0, -105.1),
	"DireMaul": Vector3(47.5, -153.7, -2.7),
}
const MAX_DROP: float = 6.0

var _failures: PackedStringArray = []


func _initialize() -> void:
	var archive: WowArchive = WowArchive.new()
	archive.open(ProjectSettings.get_setting("wowgd/client_data_dir"))
	var loader: WowLoader = WowLoader.new()
	loader.archive = archive
	for map_name: String in ENTRIES:
		var info: Dictionary = loader.get_map_info(map_name)
		var wmo: Node3D = loader.load_wmo(info["wmo"], info["wmo_doodad_set"])
		var entry: Vector3 = ENTRIES[map_name]
		var placed: float = _floor_drop(wmo, info["wmo_transform"], entry)
		var flipped: Transform3D = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) \
			* info["wmo_transform"]
		var other: float = _floor_drop(wmo, flipped, entry)
		print("%-20s floor %.1f below the entry (flipped: %.1f)" % [map_name, placed, other])
		_check(placed <= MAX_DROP, map_name + " entry stands on the WMO floor")
		wmo.free()
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("test_instances: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


# Distance from the entry point down to the nearest collision triangle under it, or INF.
func _floor_drop(wmo: Node3D, placement: Transform3D, entry: Vector3) -> float:
	var point: Vector3 = WowCoords.to_godot(entry)
	var best: float = INF
	for node: Node in wmo.find_children("*", "CollisionShape3D", true, false):
		var shape: ConcavePolygonShape3D = (node as CollisionShape3D).shape
		var faces: PackedVector3Array = shape.get_faces()
		var local: Transform3D = Transform3D()
		var walk: Node = node
		while walk != wmo:
			local = (walk as Node3D).transform * local
			walk = walk.get_parent()
		var to_world: Transform3D = placement * local
		for t: int in range(0, faces.size(), 3):
			var a: Vector3 = to_world * faces[t]
			var b: Vector3 = to_world * faces[t + 1]
			var c: Vector3 = to_world * faces[t + 2]
			var hit: Variant = Geometry3D.ray_intersects_triangle(
				point + Vector3.UP * 2.0, Vector3.DOWN, a, b, c
			)
			if hit != null:
				best = minf(best, point.y - (hit as Vector3).y)
	return best


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)
