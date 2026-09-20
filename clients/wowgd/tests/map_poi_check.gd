class_name MapPoiCheck
extends Node

const WORLD_MAP: PackedScene = preload("res://ui/world_map_frame.tscn")
# A zone with landmarks of its own, by its AreaTable id.
const ELWYNN_AREA: int = 12

var _failures: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: InterfaceSettings = WowAssets.interface
	settings.restore_defaults()
	var frame: WorldMapFrame = WORLD_MAP.instantiate()
	add_child(frame)
	await get_tree().process_frame
	frame.show_area(_world_map_area(ELWYNN_AREA))
	await get_tree().process_frame
	var with_pois: int = frame._markers.size()
	print("markers with landmarks: ", with_pois)
	_check(with_pois > 0, "Elwynn has markers")
	settings.set_on(&"show_map_pois", false)
	await get_tree().process_frame
	var without: int = frame._markers.size()
	print("markers without landmarks: ", without)
	_check(without < with_pois, "turning the option off drops the landmarks")
	settings.set_on(&"show_map_pois", true)
	await get_tree().process_frame
	_check(frame._markers.size() == with_pois, "turning it back on brings them back")
	if _failures.is_empty():
		print("map_poi_check: OK")
	else:
		for line: String in _failures:
			print("  ", line)
		print("map_poi_check: FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


# WorldMapArea rows are what the frame shows, keyed by the AreaTable zone they cover.
func _world_map_area(area_id: int) -> int:
	var areas: WowDBC = WowDBC.open(WowAssets.archive, "WorldMapArea")
	for row: int in areas.row_count():
		if areas.get_uint(row, "AreaID") == area_id:
			return areas.get_uint(row, 0)
	return -1


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)
