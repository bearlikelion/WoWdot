class_name LoadingScreen
extends Control

# Shown for maps whose Map.dbc row names no LoadingScreens entry.
const FALLBACK_IMAGE: String = "Interface\\Glues\\Loading.blp"
# Where the bright tip sits along Loading-BarGlow.
const GLOW_TIP: float = 470.0

var _fill_width: float = 0.0

@onready var _image: TextureRect = %LoadingScreenImage
@onready var _fill: Control = %LoadingBarFill
@onready var _glow: Control = %LoadingBarGlow


func _ready() -> void:
	_fill_width = _fill.size.x
	set_progress(0.0)


func open(map_id: int) -> void:
	var maps: WowDBC = WowDBC.open(WowAssets.archive, "Map")
	var screens: WowDBC = WowDBC.open(WowAssets.archive, "LoadingScreens")
	var map_row: int = maps.find(map_id)
	var screen_id: int = maps.get_uint(map_row, "LoadingScreenID") if map_row >= 0 else 0
	var screen_row: int = screens.find(screen_id) if screen_id > 0 else -1
	var image: WowTexture = WowTexture.new()
	image.file = screens.get_string(screen_row, "FileName") if screen_row >= 0 else FALLBACK_IMAGE
	_image.texture = image
	set_progress(0.0)
	show()


func set_progress(fraction: float) -> void:
	_fill.size.x = _fill_width * clampf(fraction, 0.0, 1.0)
	_fill.visible = fraction > 0.0
	_glow.visible = fraction > 0.0
	_glow.position.x = _fill.size.x - GLOW_TIP
