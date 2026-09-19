class_name MinimapCluster
extends Control

# GetZonePVPInfo colours for the zone name above the minimap.
const FRIENDLY: Color = Color(0.1, 1.0, 0.1)
const HOSTILE: Color = Color(1.0, 0.1, 0.1)
const CONTESTED: Color = Color(1.0, 0.7, 0.0)

@onready var _view: MinimapView = %Minimap
@onready var _zone_text: Label = %MinimapZoneText
@onready var _zoom_in: BaseButton = %MinimapZoomIn
@onready var _zoom_out: BaseButton = %MinimapZoomOut
@onready var _toggle: BaseButton = %MinimapToggleButton
@onready var _game_time: TextureRect = %GameTimeTexture


func _ready() -> void:
	# The zone name is tinted per PvP status, so it starts from the white font.
	_zone_text.theme_type_variation = &"GameFontHighlight"
	_zoom_in.pressed.connect(func() -> void: _view.zoom += 1)
	_zoom_out.pressed.connect(func() -> void: _view.zoom -= 1)
	_toggle.pressed.connect(func() -> void: _view.visible = not _view.visible)
	_view.zoom_changed.connect(_on_zoom_changed)
	_on_zoom_changed(_view.zoom)
	var indicator: AtlasTexture = AtlasTexture.new()
	indicator.atlas = _game_time.texture
	_game_time.texture = indicator


# GameTimeFrame_Update: the day face is the left half of the texture, the night face the right.
func _process(_delta: float) -> void:
	var indicator: AtlasTexture = _game_time.texture
	var half: Vector2 = indicator.atlas.get_size() * Vector2(0.5, 1.0)
	var left: float = half.x if WowClient.clock.is_night() else 0.0
	indicator.region = Rect2(Vector2(left, 0.0), half)


func show_location(map_dir: String, wow_position: Vector3, facing: float) -> void:
	_view.show_location(map_dir, wow_position, facing)


func show_area(area_id: int, player_race: int) -> void:
	_zone_text.text = AreaInfo.area_name(area_id)
	var owner: AreaInfo.FactionGroup = AreaInfo.faction_group(area_id)
	if owner == AreaInfo.FactionGroup.NONE:
		_zone_text.self_modulate = CONTESTED
	elif owner == AreaInfo.player_group(player_race):
		_zone_text.self_modulate = FRIENDLY
	else:
		_zone_text.self_modulate = HOSTILE


func _on_zoom_changed(zoom: int) -> void:
	_zoom_out.disabled = zoom == 0
	_zoom_in.disabled = zoom == MinimapView.ZOOM_DIAMETERS.size() - 1
