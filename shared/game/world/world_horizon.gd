class_name WorldHorizon
extends MeshInstance3D

@export var map: WowMap

var _pending: bool = false


func _ready() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if map:
		map.tile_loaded.connect(func(_tile: Vector2i) -> void: _rebuild_later())
		map.tile_unloaded.connect(func(_tile: Vector2i) -> void: _rebuild_later())


# One rebuild per frame however many tiles change, since the whole map is one mesh.
func _rebuild_later() -> void:
	if _pending:
		return
	_pending = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_pending = false
	var skipped: PackedVector2Array = []
	for tile: Vector2i in map.loaded_tiles():
		skipped.append(Vector2(tile))
	mesh = WowAssets.loader.load_wdl(map.map_name, skipped)
