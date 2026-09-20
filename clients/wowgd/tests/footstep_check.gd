class_name FootstepCheck
extends Node3D

const TILE: Vector2i = Vector2i(31, 49)
const TILE_SIZE: float = 1600.0 / 3.0
const SAMPLES: int = 64
const HUMAN_DISPLAY_ID: int = 49
const GROUND_TERRAIN_COLUMN: int = 6
const LOAD_TIMEOUT_MS: int = 120000

@onready var _map: WowMap = $WowMap

var _failures: PackedStringArray = []


func _ready() -> void:
	await _wait_for_tile()
	_check(_map.loaded_tiles().has(TILE), "the Goldshire tile loads")
	UnitVoice.map = _map
	var ground: WowDBC = WowDBC.open(WowAssets.archive, "GroundEffectTexture")
	var counts: Dictionary[int, int] = {}
	var where: Dictionary[int, Vector3] = {}
	var named: int = 0
	for row: int in SAMPLES:
		for column: int in SAMPLES:
			var point: Vector3 = _sample_point(row, column)
			var effect: int = _map.ground_effect_at(point)
			if effect == 0:
				continue
			named += 1
			var terrain: int = ground.get_uint(ground.find(effect), GROUND_TERRAIN_COLUMN)
			counts[terrain] = counts.get(terrain, 0) + 1
			where[terrain] = point
	print("ground effects named: %d of %d samples" % [named, SAMPLES * SAMPLES])
	print("terrain types: ", counts)
	_check(named > SAMPLES * SAMPLES / 2, "most of the tile names a ground effect")
	_check(counts.size() >= 2, "the tile has more than one terrain type")
	_check_voice(where)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("footstep_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


# A human standing on each of the tile's terrains reads it back and has a footstep for it.
func _check_voice(where: Dictionary[int, Vector3]) -> void:
	var model: Node3D = Node3D.new()
	add_child(model)
	UnitVoice.attach(model, 1, HUMAN_DISPLAY_ID)
	var voice: UnitVoice = UnitVoice.by_guid[1]
	var heard: Dictionary[int, bool] = {}
	for terrain: int in where:
		model.global_position = where[terrain]
		var names: PackedStringArray = UnitVoice.Terrain.keys()
		_check(voice._terrain_under() == terrain, "%s reads back at its own cell" % names[terrain])
		var step: int = UnitVoice._footsteps.get(Vector2i(voice._footstep_id, terrain), 0)
		var splash: int = UnitVoice._splashes.get(Vector2i(voice._footstep_id, terrain), 0)
		_check(step > 0, "a human has a %s footstep" % names[terrain])
		_check(step != splash, "%s splashes differently" % names[terrain])
		heard[step] = true
	print("distinct footsteps over this tile: ", heard.size())
	_check(heard.size() >= 3, "the tile's terrains do not all sound alike")


func _sample_point(row: int, column: int) -> Vector3:
	return WowCoords.to_godot(Vector3(
		(32.0 - TILE.y) * TILE_SIZE - (row + 0.5) * TILE_SIZE / SAMPLES,
		(32.0 - TILE.x) * TILE_SIZE - (column + 0.5) * TILE_SIZE / SAMPLES,
		0.0,
	))


func _wait_for_tile() -> void:
	var deadline: int = Time.get_ticks_msec() + LOAD_TIMEOUT_MS
	await get_tree().process_frame
	await get_tree().process_frame
	while not _map.is_idle() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)
