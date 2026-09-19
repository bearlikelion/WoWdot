class_name MinimapView
extends Control

signal zoom_changed(zoom: int)

const TILE_YARDS: float = 1600.0 / 3.0
# Outdoor minimap diameters in yards for zoom levels 0 to 5.
const ZOOM_DIAMETERS: Array[float] = [466.6667, 400.0, 333.3333, 266.6667, 200.0, 133.3333]
const MASK: Shader = preload("res://game/ui/minimap.gdshader")

var zoom: int = 0:
	set(value):
		zoom = clampi(value, 0, ZOOM_DIAMETERS.size() - 1)
		queue_redraw()
		zoom_changed.emit(zoom)

var _map_dir: String = ""
var _position: Vector3 = Vector3.ZERO

@onready var _arrow: TextureRect = %MinimapArrow


func _ready() -> void:
	var mask: ShaderMaterial = ShaderMaterial.new()
	mask.shader = MASK
	mask.set_shader_parameter("size", size)
	material = mask
	resized.connect(func() -> void: mask.set_shader_parameter("size", size))
	_arrow.pivot_offset = _arrow.size / 2.0


# WoW position (yards) and facing of the player on the named map directory, such as "Azeroth".
func show_location(map_dir: String, wow_position: Vector3, facing: float) -> void:
	_map_dir = map_dir
	_position = wow_position
	# The arrow points north at facing 0; WoW facing grows counter-clockwise.
	_arrow.rotation = -facing
	queue_redraw()


func _draw() -> void:
	if _map_dir.is_empty():
		return
	var yards_per_pixel: float = ZOOM_DIAMETERS[zoom] / size.x
	# Tile coordinates grow east (x) and south (y), the way the minimap images are drawn.
	var center: Vector2 = Vector2(32.0 - _position.y / TILE_YARDS, 32.0 - _position.x / TILE_YARDS)
	var tile_pixels: float = TILE_YARDS / yards_per_pixel
	var reach: float = ZOOM_DIAMETERS[zoom] / TILE_YARDS / 2.0 + 1.0
	for tile_x: int in range(floori(center.x - reach), ceili(center.x + reach)):
		for tile_y: int in range(floori(center.y - reach), ceili(center.y + reach)):
			var image: WowTexture = MinimapTiles.texture(_map_dir, Vector2i(tile_x, tile_y))
			if image == null:
				continue
			var corner: Vector2 = size / 2.0 + (Vector2(tile_x, tile_y) - center) * tile_pixels
			draw_texture_rect(image, Rect2(corner, Vector2(tile_pixels, tile_pixels)), false)
