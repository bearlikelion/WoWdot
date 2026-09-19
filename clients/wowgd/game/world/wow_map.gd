@tool
class_name WowMap
extends Node3D

signal tile_loaded(tile: Vector2i)

const TILE_SIZE: float = 1600.0 / 3.0
const FOCUS_MARKER_SIZE: float = 60.0
const FOCUS_ARRIVAL_FRAMES: int = 120

@export var map_name: String = "Azeroth":
	set(value):
		map_name = value
		if is_inside_tree():
			_reset()
			if Engine.is_editor_hint():
				_auto_focus()
## Tiles stream around this node; in the editor the 3D viewport camera is used when unset.
@export var target: Node3D
@export_range(0, 4) var radius: int = 1
@export var load_placements: bool = true
@export_group("Editor")
## WoW coordinates for the focus marker; select it and press F to move the editor camera there.
@export var editor_position: Vector3 = Vector3(-9460.0, 62.0, 120.0)
@export_tool_button("Place focus marker") var place_focus_marker: Callable = _place_focus_marker

var _streamer: WowStreamer = WowStreamer.new()
var _existing: Dictionary[Vector2i, bool] = {}
var _tiles: Dictionary[Vector2i, Node3D] = {}
var _loading: Dictionary[Vector2i, bool] = {}
var _tile_placements: Dictionary[Vector2i, PackedInt64Array] = {}
var _placement_nodes: Dictionary[int, Node3D] = {}
var _root_wmo: Node3D
var _focus_tile: Vector2i
var _awaiting_focus_tile: bool = false
var _camera_moving: bool = false


func _ready() -> void:
	_streamer.loader = WowAssets.loader
	# The headless dummy renderer cannot create resources from worker threads.
	_streamer.threaded = DisplayServer.get_name() != "headless"
	_reset()
	if Engine.is_editor_hint() and get_node_or_null("Focus") == null:
		_auto_focus()


func _process(_delta: float) -> void:
	for result: Dictionary in _streamer.poll():
		_attach(result)
	# Hold streaming until the editor camera reaches the new map, or its first tile would unload.
	if _awaiting_focus_tile or _camera_moving:
		return
	var focus: Node3D = _focus()
	if focus == null:
		return
	_streamer.load_placements = load_placements
	var center: Vector2i = tile_at(focus.global_position)
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			var tile: Vector2i = Vector2i(x, y)
			if _existing.has(tile) and not _tiles.has(tile) and not _loading.has(tile):
				_loading[tile] = true
				_streamer.request(map_name, tile)
	# One extra tile of slack so walking along a border does not reload tiles.
	for tile: Vector2i in _tiles.keys():
		var offset: Vector2i = (tile - center).abs()
		if maxi(offset.x, offset.y) > radius + 1:
			_unload(tile)


func _validate_property(property: Dictionary) -> void:
	if property.name == "map_name" and Engine.is_editor_hint():
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ",".join(_map_names())


func tile_at(godot_position: Vector3) -> Vector2i:
	var wow: Vector3 = WowCoords.from_godot(godot_position)
	return Vector2i(floori(32.0 - wow.y / TILE_SIZE), floori(32.0 - wow.x / TILE_SIZE))


# The AreaTable id of the terrain chunk under the position, or 0 while its tile is not loaded.
func area_id_at(godot_position: Vector3) -> int:
	var tile: Vector2i = tile_at(godot_position)
	if not _tiles.has(tile):
		return 0
	var wow: Vector3 = WowCoords.from_godot(godot_position)
	var chunk_x: int = clampi(floori((32.0 - wow.y / TILE_SIZE - tile.x) * 16.0), 0, 15)
	var chunk_y: int = clampi(floori((32.0 - wow.x / TILE_SIZE - tile.y) * 16.0), 0, 15)
	var area_ids: PackedInt32Array = _tiles[tile].get_meta("area_ids", PackedInt32Array())
	return area_ids[chunk_y * 16 + chunk_x] if area_ids.size() == 256 else 0


# True once collision under the point exists; maps without terrain tiles are a single WMO.
func is_ground_ready(godot_position: Vector3) -> bool:
	return _existing.is_empty() or _tiles.has(tile_at(godot_position))


# The share of the map's tiles around the point that have loaded, 1.0 when there are none to load.
func load_progress(godot_position: Vector3) -> float:
	var center: Vector2i = tile_at(godot_position)
	var wanted: int = 0
	var loaded: int = 0
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			if _existing.has(Vector2i(x, y)):
				wanted += 1
				loaded += int(_tiles.has(Vector2i(x, y)))
	return float(loaded) / wanted if wanted > 0 else 1.0


func is_idle() -> bool:
	return _loading.is_empty()


func loaded_tiles() -> Array[Vector2i]:
	return _tiles.keys()


func _focus() -> Node3D:
	if target:
		return target
	if Engine.is_editor_hint():
		var editor: Object = Engine.get_singleton("EditorInterface")
		return editor.get_editor_viewport_3d(0).get_camera_3d()
	return null


func _map_names() -> PackedStringArray:
	var names: PackedStringArray = []
	var maps: WowDBC = WowDBC.open(WowAssets.archive, "Map")
	for row: int in maps.row_count():
		names.append(maps.get_string(row, "InternalName"))
	return names


func _place_focus_marker() -> void:
	_focus_editor_on(WowCoords.to_godot(editor_position))


func _auto_focus() -> void:
	if _root_wmo:
		_focus_editor_on(_bounds(_root_wmo).get_center())
		return
	if _existing.is_empty():
		push_warning("WowMap: %s has no terrain tiles or root WMO" % map_name)
		return
	var box: Rect2i = Rect2i(_existing.keys()[0], Vector2i.ONE)
	for tile: Vector2i in _existing:
		box = box.expand(tile)
	var middle: Vector2 = Vector2(box.get_center())
	_focus_tile = _existing.keys()[0]
	for tile: Vector2i in _existing:
		if Vector2(tile).distance_to(middle) < Vector2(_focus_tile).distance_to(middle):
			_focus_tile = tile
	_awaiting_focus_tile = true
	_loading[_focus_tile] = true
	_streamer.request(map_name, _focus_tile)


func _focus_editor_on(point: Vector3) -> void:
	var editor: Object = Engine.get_singleton("EditorInterface")
	var marker: Marker3D = get_node_or_null("Focus")
	if marker == null:
		marker = Marker3D.new()
		marker.name = "Focus"
		add_child(marker)
		marker.owner = editor.get_edited_scene_root()
	# The marker's gizmo size sets how far Focus Selection pulls the camera back.
	marker.gizmo_extents = FOCUS_MARKER_SIZE
	marker.global_position = point
	editor_position = WowCoords.from_godot(point)
	editor.get_selection().clear()
	editor.get_selection().add_node(marker)
	_camera_moving = true
	# The 3D editor picks up a new selection a frame later; focusing before that frames nothing.
	var tree: SceneTree = get_tree()
	await tree.process_frame
	await tree.process_frame
	if not is_inside_tree():
		_camera_moving = false
		return
	_press_focus_selection(editor)
	var camera: Camera3D = editor.get_editor_viewport_3d(0).get_camera_3d()
	for i: int in FOCUS_ARRIVAL_FRAMES:
		if not is_inside_tree() or tile_at(camera.global_position) == tile_at(point):
			break
		await tree.process_frame
	_camera_moving = false


# Runs the viewport's Focus Selection item, matched by shortcut so a rebound key still works.
func _press_focus_selection(editor: Object) -> void:
	var settings: Object = editor.get_editor_settings()
	var shortcut: Shortcut = settings.get_shortcut("spatial_editor/focus_selection")
	var viewport: Node = editor.get_editor_viewport_3d(0)
	while viewport and viewport.get_class() != "Node3DEditorViewport":
		viewport = viewport.get_parent()
	if viewport == null or shortcut == null:
		return
	for menu: Node in viewport.find_children("*", "MenuButton", true, false):
		var popup: PopupMenu = (menu as MenuButton).get_popup()
		for i: int in popup.item_count:
			if popup.get_item_shortcut(i) == shortcut:
				popup.id_pressed.emit(popup.get_item_id(i))
				return


func _bounds(root: Node3D) -> AABB:
	var box: AABB = AABB(root.global_position, Vector3.ZERO)
	var first: bool = true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node
		var mesh_box: AABB = mesh.global_transform * mesh.get_aabb()
		box = mesh_box if first else box.merge(mesh_box)
		first = false
	return box


func _reset() -> void:
	for tile: Vector2i in _tiles.keys():
		_unload(tile)
	_streamer.reset()
	_loading.clear()
	if _root_wmo:
		_root_wmo.queue_free()
		_root_wmo = null
	_existing.clear()
	var info: Dictionary = WowAssets.loader.get_map_info(map_name)
	for tile: Vector2i in info.get("tiles", []):
		_existing[tile] = true
	# WMO-only maps (most dungeons) are a single root WMO with no terrain.
	if info.has("wmo"):
		_root_wmo = WowAssets.loader.load_wmo(info["wmo"], info["wmo_doodad_set"])
		if _root_wmo:
			_root_wmo.transform = info["wmo_transform"]
			add_child(_root_wmo)


func _attach(result: Dictionary) -> void:
	var tile: Vector2i = result["tile"]
	_loading.erase(tile)
	var node: Node3D = result["node"]
	if node == null:
		_existing.erase(tile)
		return
	add_child(node)
	_tiles[tile] = node
	_tile_placements[tile] = result["refs"]
	var built: Dictionary = result["built"]
	for unique_id: int in built:
		_placement_nodes[unique_id] = built[unique_id]
		add_child(built[unique_id])
	tile_loaded.emit(tile)
	if _awaiting_focus_tile and tile == _focus_tile:
		_awaiting_focus_tile = false
		var terrain: MeshInstance3D = node.get_node("Terrain")
		_focus_editor_on((terrain.global_transform * terrain.get_aabb()).get_center())


func _unload(tile: Vector2i) -> void:
	_tiles[tile].queue_free()
	_tiles.erase(tile)
	for unique_id: int in _streamer.release(_tile_placements.get(tile, PackedInt64Array())):
		if _placement_nodes.has(unique_id):
			_placement_nodes[unique_id].queue_free()
			_placement_nodes.erase(unique_id)
	_tile_placements.erase(tile)
