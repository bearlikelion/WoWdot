class_name TestTerrain
extends SceneTree

const SERVER_MAPS: String = "/mnt/Storage/mWoW/Vanilla/server/data/maps/"
const GOLDSHIRE_TILE: Vector2i = Vector2i(31, 49)
const HEIGHT_GRID: int = 257
const HEIGHT_STEP: float = (1600.0 / 3.0) / 256.0
const MAP_HEIGHT_NO_HEIGHT: int = 0x1
const MAP_HEIGHT_AS_INT16: int = 0x2
const MAP_HEIGHT_AS_INT8: int = 0x4
const MAX_ERROR: float = 0.01

var _failures: PackedStringArray = []


func _initialize() -> void:
	var archive: WowArchive = WowArchive.new()
	archive.open(ProjectSettings.get_setting("wowgd/client_data_dir"))
	var loader: WowLoader = WowLoader.new()
	loader.archive = archive

	var info: Dictionary = loader.get_map_info("Azeroth")
	_check(GOLDSHIRE_TILE in info["tiles"], "Azeroth WDT lists the Goldshire tile")
	var tile: Node3D = loader.load_adt("Azeroth", GOLDSHIRE_TILE.x, GOLDSHIRE_TILE.y)
	_check(tile != null, "Goldshire ADT loads")
	if tile:
		var terrain: MeshInstance3D = tile.get_node("Terrain")
		_check(terrain.mesh.get_surface_count() == 256, "one surface per chunk")
		_check(not (tile.get_meta("placements", []) as Array).is_empty(), "tile lists placements")
		_compare_with_server(tile)
		tile.free()

	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("test_terrain: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


# The server's extracted .map holds the same MCVT heights: V9 at quad corners, V8 at quad centres.
func _compare_with_server(tile: Node3D) -> void:
	var path: String = SERVER_MAPS + "000%02d%02d.map" % [GOLDSHIRE_TILE.y, GOLDSHIRE_TILE.x]
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("skipping server comparison, no ", path)
		return
	file.seek(16)
	var height_offset: int = file.get_32()
	file.seek(height_offset + 4)
	var flags: int = file.get_32()
	var packed: int = MAP_HEIGHT_NO_HEIGHT | MAP_HEIGHT_AS_INT16 | MAP_HEIGHT_AS_INT8
	_check((flags & packed) == 0, "float heights")
	file.seek(height_offset + 16)
	var v9: PackedFloat32Array = file.get_buffer(129 * 129 * 4).to_float32_array()
	var v8: PackedFloat32Array = file.get_buffer(128 * 128 * 4).to_float32_array()

	var shapes: Array[Node] = tile.find_children("*", "CollisionShape3D", true, false)
	var shape: HeightMapShape3D = (shapes[0] as CollisionShape3D).shape
	var ours: PackedFloat32Array = shape.map_data
	var worst: float = 0.0
	for a: int in 129:
		for b: int in 129:
			var corner: float = ours[(2 * a) * HEIGHT_GRID + 2 * b] * HEIGHT_STEP
			worst = max(worst, absf(corner - v9[a * 129 + b]))
	for a: int in 128:
		for b: int in 128:
			var centre: float = ours[(2 * a + 1) * HEIGHT_GRID + 2 * b + 1] * HEIGHT_STEP
			worst = max(worst, absf(centre - v8[a * 128 + b]))
	print("largest height difference against the server map: %.4f" % worst)
	_check(worst < MAX_ERROR, "collision heights match the server map")


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)
