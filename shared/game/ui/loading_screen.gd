class_name LoadingScreen
extends Control

# Shown for maps whose Map.dbc row names no LoadingScreens entry.
const FALLBACK_IMAGE: String = "Interface\\Glues\\Loading.blp"
# Where the bright tip sits along Loading-BarGlow.
const GLOW_TIP: float = 470.0

# The tip block is this wide against a 4:3 screen of the window's height, and sits this far up it.
const TIP_WIDTH: float = 515.0 / 1024.0 * 4.0 / 3.0
const TIP_BOTTOM: float = 0.1
# The bar's art reaches this far up from the bottom, and the tip stays clear of it.
const BAR_TOP: float = 84.0
const TIP_SETTINGS: String = "user://interface.cfg"
const TIP_SECTION: String = "game_tips"

var _fill_width: float = 0.0

@onready var _image: TextureRect = %LoadingScreenImage
@onready var _fill: Control = %LoadingBarFill
@onready var _glow: Control = %LoadingBarGlow
@onready var _tip: RichTextLabel = %GameTip


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
	_show_tip()
	set_progress(0.0)
	show()


# The stock client walks GameTips.dbc in order, storing the row the next load will show.
func _show_tip() -> void:
	var tips: WowDBC = WowDBC.open(WowAssets.archive, "GameTips")
	_tip.visible = tips != null and tips.row_count() > 0 \
	and WowAssets.interface.is_on(&"show_game_tips")
	if not _tip.visible:
		return
	var saved: ConfigFile = ConfigFile.new()
	saved.load(TIP_SETTINGS)
	var row: int = saved.get_value(TIP_SECTION, "next", 0)
	if row < 0 or row >= tips.row_count():
		row = 0
	saved.set_value(TIP_SECTION, "next", row + 1)
	saved.save(TIP_SETTINGS)
	_tip.text = WowStrings.to_bbcode(tips.get_string(row, 1).strip_edges())
	var width: float = size.y * TIP_WIDTH
	_tip.offset_left = -width / 2.0
	_tip.offset_right = width / 2.0
	_tip.offset_bottom = -maxf(size.y * TIP_BOTTOM, BAR_TOP)


func set_progress(fraction: float) -> void:
	_fill.size.x = _fill_width * clampf(fraction, 0.0, 1.0)
	_fill.visible = fraction > 0.0
	_glow.visible = fraction > 0.0
	_glow.position.x = _fill.size.x - GLOW_TIP
