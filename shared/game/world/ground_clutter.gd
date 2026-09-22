class_name GroundClutter
extends Node3D

# GroundEffectTexture.dbc: four doodad slots and a density; GroundEffectDoodad.dbc names models.
const DOODAD_COLUMNS: PackedInt32Array = [1, 2, 3, 4]
const DENSITY_COLUMN: int = 5
const EMPTY_SLOT: int = 0xFFFFFFFF
const INTERNAL_ID_COLUMN: int = 1
const MODEL_COLUMN: int = 2
const DETAIL_PATH: String = "World\\NoDXT\\Detail\\"
# The stock client fades its detail doodads out by 70 yards, and seeds 16 cells per chunk.
const REACH: float = 70.0
const CELLS_PER_CHUNK: int = 16
const CHUNK_YARDS: float = WowMap.TILE_SIZE / 16.0
const CELL_YARDS: float = CHUNK_YARDS / 8.0
const HEIGHT_GRID: int = 257

@export var map: WowMap
@export var player: Node3D

var _textures: WowDBC
var _doodads: WowDBC
var _models: Dictionary[int, String] = {}
var _meshes: Dictionary[String, Mesh] = {}
var _built: Dictionary[Vector3i, Node3D] = {}
var _last_chunk: Vector3i = Vector3i(-1, -1, -1)


func _ready() -> void:
	_textures = WowDBC.open(WowAssets.archive, "GroundEffectTexture")
	_doodads = WowDBC.open(WowAssets.archive, "GroundEffectDoodad")
	for row: int in _doodads.row_count():
		var file: String = _doodads.get_string(row, MODEL_COLUMN).replace(".mdl", ".m2")
		_models[_doodads.get_uint(row, INTERNAL_ID_COLUMN)] = DETAIL_PATH + file
	if map:
		map.tile_loaded.connect(func(_tile: Vector2i) -> void: _last_chunk = Vector3i(-1, -1, -1))


func _process(_delta: float) -> void:
	if map == null or player == null:
		return
	var tile: Vector2i = map.tile_at(player.global_position)
	var chunk: Vector3i = Vector3i(tile.x, tile.y, map.chunk_index_at(player.global_position))
	if chunk == _last_chunk:
		return
	_last_chunk = chunk
	var reach_chunks: int = ceili(REACH / CHUNK_YARDS)
	var wanted: Dictionary[Vector3i, bool] = {}
	var here: Vector2i = Vector2i(tile.x * 16 + chunk.z % 16, tile.y * 16 + chunk.z / 16)
	for dy: int in range(-reach_chunks, reach_chunks + 1):
		for dx: int in range(-reach_chunks, reach_chunks + 1):
			var global: Vector2i = here + Vector2i(dx, dy)
			@warning_ignore("integer_division")
			var key: Vector3i = Vector3i(global.x / 16, global.y / 16, (global.y % 16) * 16 + global.x % 16)
			wanted[key] = true
			if not _built.has(key) and map.loaded_tiles().has(Vector2i(key.x, key.y)):
				_built[key] = _build(key)
	for key: Vector3i in _built.keys():
		if not wanted.has(key) or not is_instance_valid(_built[key]):
			if is_instance_valid(_built[key]):
				_built[key].queue_free()
			_built.erase(key)


# One MultiMesh per model, scattered over the cells whose top layer carries a ground effect.
func _build(key: Vector3i) -> Node3D:
	var holder: Node3D = Node3D.new()
	add_child(holder)
	var tile_node: Node3D = map.tile_node(Vector2i(key.x, key.y))
	if tile_node == null:
		return holder
	var effects: PackedInt32Array = tile_node.get_meta("ground_effects", PackedInt32Array())
	var shape: HeightMapShape3D = _height_shape(tile_node)
	if effects.is_empty() or shape == null:
		return holder
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(key)
	var transforms: Dictionary[String, Array] = {}
	var chunk_x: int = key.z % 16
	@warning_ignore("integer_division")
	var chunk_y: int = key.z / 16
	for i: int in CELLS_PER_CHUNK:
		var cell: Vector2i = Vector2i(rng.randi() & 7, rng.randi() & 7)
		var effect: int = effects[key.z * WowMap.GROUND_CELLS + cell.y * 8 + cell.x]
		var row: int = _textures.find(effect) if effect > 0 else -1
		if row < 0:
			continue
		var density: int = _textures.get_uint(row, DENSITY_COLUMN)
		density = 8 if density == 0 else density
		for n: int in density:
			var fx: float = rng.randf()
			var fy: float = rng.randf()
			var slot: int = _textures.get_uint(row, DOODAD_COLUMNS[(n + i) & 3])
			if slot == EMPTY_SLOT or not _models.has(slot):
				continue
			var scale: float = rng.randf_range(0.9, 1.1)
			var yaw: float = rng.randf_range(-PI, PI)
			var east: float = (chunk_x * 8 + cell.x + fx) * CELL_YARDS
			var south: float = (chunk_y * 8 + cell.y + fy) * CELL_YARDS
			var local: Vector3 = _tile_point(tile_node, shape, east, south)
			var placed: Transform3D = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), local)
			if not transforms.has(_models[slot]):
				transforms[_models[slot]] = []
			transforms[_models[slot]].append(placed)
	for path: String in transforms:
		var mesh: Mesh = _mesh(path)
		if mesh == null:
			continue
		var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
		instance.multimesh = MultiMesh.new()
		instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		instance.multimesh.mesh = mesh
		instance.multimesh.instance_count = transforms[path].size()
		for j: int in transforms[path].size():
			instance.multimesh.set_instance_transform(j, transforms[path][j])
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = REACH
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(instance)
	return holder


# The tile's north west corner is its origin; east runs along +X and south along +Z.
func _tile_point(tile_node: Node3D, shape: HeightMapShape3D, east: float, south: float) -> Vector3:
	var step: float = WowMap.TILE_SIZE / (HEIGHT_GRID - 1)
	var column: float = east / step
	var row: float = south / step
	var c0: int = clampi(floori(column), 0, HEIGHT_GRID - 2)
	var r0: int = clampi(floori(row), 0, HEIGHT_GRID - 2)
	var data: PackedFloat32Array = shape.map_data
	var h00: float = data[r0 * HEIGHT_GRID + c0]
	var h10: float = data[r0 * HEIGHT_GRID + c0 + 1]
	var h01: float = data[(r0 + 1) * HEIGHT_GRID + c0]
	var h11: float = data[(r0 + 1) * HEIGHT_GRID + c0 + 1]
	var height: float = lerpf(lerpf(h00, h10, column - c0), lerpf(h01, h11, column - c0), row - r0)
	var origin: Vector3 = _collision_origin(tile_node) - Vector3.ONE * (WowMap.TILE_SIZE / 2.0)
	# The shape is scaled by the grid step on every axis, so its samples are heights over that step.
	return Vector3(origin.x + east, height * step, origin.z + south)


func _collision_origin(tile_node: Node3D) -> Vector3:
	var collision: CollisionShape3D = tile_node.get_node("Collision").get_child(0)
	return collision.position


func _height_shape(tile_node: Node3D) -> HeightMapShape3D:
	var collision: Node = tile_node.get_node_or_null("Collision")
	return (collision.get_child(0) as CollisionShape3D).shape if collision else null


func _mesh(path: String) -> Mesh:
	if not _meshes.has(path):
		var model: Node3D = WowAssets.loader.load_m2(path)
		var found: Array[Node] = model.find_children("*", "MeshInstance3D", true, false) if model else []
		_meshes[path] = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
		if model:
			model.queue_free()
	return _meshes[path]
