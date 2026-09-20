class_name TerrainCheck
extends Node

const CHUNKS: int = 256
# Tiles whose ADT carries MH2O water: Northshire's stream and a Borean Tundra coast.
const TILES: Array[Dictionary] = [
	{ "map": "Azeroth", "x": 32, "y": 48 },
	{ "map": "Northrend", "x": 34, "y": 22 },
]
# LiquidType.dbc row ids against the four liquid materials their Type column picks.
const LIQUIDS: Dictionary[int, int] = { 1: 0, 2: 1, 3: 2, 4: 3 }

var _failures: PackedStringArray = []


func _ready() -> void:
	var loader: WowLoader = WowLoader.get_shared()
	_check_liquid_types(loader)
	for tile: Dictionary in TILES:
		_check_tile(loader, tile["map"], tile["x"], tile["y"])
	_finish()


# MH2O names one of these rows where vanilla's MCLQ named the material outright.
func _check_liquid_types(loader: WowLoader) -> void:
	var liquids: WowDBC = WowDBC.open(loader.get_archive(), "LiquidType")
	if not _check(liquids != null, "LiquidType.dbc reads out of the archives"):
		return
	for id: int in LIQUIDS:
		var row: int = liquids.find(id)
		if not _check(row >= 0, "LiquidType.dbc has row %d" % id):
			continue
		_check(liquids.get_uint(row, "Type") == LIQUIDS[id],
				"%s is material %d" % [liquids.get_string(row, "Name"), LIQUIDS[id]])


func _check_tile(loader: WowLoader, map_name: String, x: int, y: int) -> void:
	var root: Node3D = loader.load_adt(map_name, x, y)
	if not _check(root != null, "%s_%d_%d loads" % [map_name, x, y]):
		return
	var terrain: MeshInstance3D = root.find_child("Terrain", true, false)
	var liquid: MeshInstance3D = root.find_child("Liquid", true, false)
	var chunks: int = terrain.mesh.get_surface_count() if terrain != null and terrain.mesh != null else 0
	var waters: int = liquid.mesh.get_surface_count() if liquid != null and liquid.mesh != null else 0
	print("%s_%d_%d: %d terrain chunks, %d liquid surfaces" % [map_name, x, y, chunks, waters])
	_check(chunks == CHUNKS, "%s_%d_%d builds a chunk of terrain for each of the %d" % [map_name, x, y, CHUNKS])
	_check(waters > 0, "%s_%d_%d builds its MH2O water" % [map_name, x, y])
	root.free()


func _check(condition: bool, what: String) -> bool:
	if not condition:
		_failures.append(what)
	return condition


func _finish() -> void:
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("terrain_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
