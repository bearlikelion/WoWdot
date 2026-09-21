class_name WorldMapFrame
extends Control

signal close_requested

const NUM_WORLDMAP_DETAIL_TILES: int = 12
const TILE_SIZE: float = 256.0
const TILE_PATH: String = "Interface\\WorldMap\\%s\\%s%d.blp"
const WORLD: String = "World"
const ARROW_PATH: String = "Interface\\Minimap\\MinimapArrow.blp"
const ARROW_SIZE: float = 32.0
const POSITION_SECONDS: float = 2.0
const MARKER: PackedScene = preload("res://game/ui/world_map_marker.tscn")
const EXPLORED_WORDS: int = 64
const ALLIANCE_RACES: Array[int] = [1, 3, 4, 7]
# The world map's two continents, by the half of the world map they sit in.
const WORLD_CONTINENTS: Array[int] = [1, 0]
# Landmarks this important get a name at zone level, and a bigger dot.
const LABELLED_IMPORTANCE: int = 1
const MAJOR_IMPORTANCE: int = 2
const LABEL_OFFSET: Vector2 = Vector2(10.0, -8.0)

# The WorldMapArea row shown: a continent (area 0), a zone, or -1 for the world.
var _shown: int = -1
var _map_ids: Dictionary[String, int] = {}
var _player_map: int = -1
# Where the player's corpse lies while they are a ghost, and the map it is on.
var _corpse_map: int = -1
var _corpse_position: Vector3 = Vector3.ZERO
var _player_area: int = 0
var _player_position: Vector3 = Vector3.ZERO
var _player_facing: float = 0.0
var _areas: WowDBC
var _area_table: WowDBC
var _overlays: WowDBC
var _pois: WowDBC
var _maps: WowDBC
var _overlay_pieces: Array[TextureRect] = []
var _markers: Array[Control] = []
var _position_wait: float = 0.0
var _labels: Array[Label] = []
var _arrow: TextureRect

@onready var _detail: Control = %WorldMapDetailFrame
@onready var _button: BaseButton = %WorldMapButton
@onready var _area_label: Label = %WorldMapFrameAreaLabel


func _ready() -> void:
	var archive: WowArchive = WowAssets.archive
	_areas = WowDBC.open(archive, "WorldMapArea")
	_area_table = WowDBC.open(archive, "AreaTable")
	_overlays = WowDBC.open(archive, "WorldMapOverlay")
	_pois = WowDBC.open(archive, "AreaPOI")
	_maps = WowDBC.open(archive, "Map")
	_detail.clip_contents = true
	# Continent and zone menus wait on a dropdown port; clicks and zoom out move around instead.
	for node_name: String in [
		"WorldMapContinentDropDown", "WorldMapZoneDropDown", "WorldMapMagnifyingGlassButton",
		"WorldMapTooltip", "WorldMapHighlight",
	]:
		(get_node("%" + node_name) as CanvasItem).hide()
	var arrow_texture: WowTexture = WowTexture.new()
	arrow_texture.file = ARROW_PATH
	_arrow = TextureRect.new()
	_arrow.texture = arrow_texture
	_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_arrow.size = Vector2.ONE * ARROW_SIZE
	_arrow.pivot_offset = _arrow.size / 2.0
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(_arrow)
	_button.gui_input.connect(_on_map_input)
	%WorldMapZoomOutButton.pressed.connect(_zoom_out)
	%WorldMapFrameCloseButton.pressed.connect(close_requested.emit)
	visibility_changed.connect(_on_visibility_changed)
	WowAssets.interface.changed.connect(_update_markers)
	WowClient.battlegrounds.positions_changed.connect(_update_markers)


func _process(delta: float) -> void:
	if not visible:
		return
	_position_wait -= delta
	if _position_wait <= 0.0 and WowClient.battlegrounds.in_battle():
		_position_wait = POSITION_SECONDS
		WowClient.battlegrounds.request_positions()
	var point: Vector2 = _map_point(_player_map, _player_position)
	_arrow.visible = point.x >= 0.0 and point.x <= 1.0 and point.y >= 0.0 and point.y <= 1.0
	_arrow.position = point * _button.size - _arrow.size / 2.0
	_arrow.rotation = -_player_facing
	var cursor: Vector2 = _button.get_local_mouse_position() / _button.size
	var zone: int = _zone_at(cursor) if _is_continent(_shown) else -1
	_area_label.text = _areas.get_string(_areas.find(zone), "AreaName") if zone >= 0 else ""


# The corpse the player has to walk back to, or map -1 once they are alive again.
func set_corpse(map_id: int, wow_position: Vector3) -> void:
	_corpse_map = map_id
	_corpse_position = wow_position
	if is_visible_in_tree():
		_update_markers()


# The HUD passes where the player is each frame, as it does for the minimap.
func set_player(map_name: String, wow_position: Vector3, facing: float, area_id: int) -> void:
	if not _map_ids.has(map_name):
		for row: int in _maps.row_count():
			if _maps.get_string(row, "InternalName") == map_name:
				_map_ids[map_name] = _maps.get_uint(row, "ID")
	_player_map = _map_ids.get(map_name, -1)
	_player_position = wow_position
	_player_facing = facing
	_player_area = area_id


# WorldMapFrame_Update: the map's twelve tiles, the explored overlays, then the landmarks.
func show_area(area_row_id: int) -> void:
	_shown = area_row_id
	var row: int = _areas.find(area_row_id)
	var file: String = _areas.get_string(row, "AreaName") if row >= 0 else WORLD
	for i: int in NUM_WORLDMAP_DETAIL_TILES:
		var tile: TextureRect = get_node("%%WorldMapDetailTile%d" % (i + 1))
		var texture: WowTexture = WowTexture.new()
		texture.file = TILE_PATH % [file, file, i + 1]
		tile.texture = texture
	(%WorldMapZoomOutButton as BaseButton).disabled = _shown < 0
	_update_overlays(file)
	_update_markers()


# GetMapOverlayInfo: explored areas lift the fog in 256 pixel pieces cut to the art's real size.
func _update_overlays(file: String) -> void:
	for piece: TextureRect in _overlay_pieces:
		piece.queue_free()
	_overlay_pieces.clear()
	if _shown < 0:
		return
	for row: int in _overlays.row_count():
		if _overlays.get_uint(row, "MapAreaID") != _shown or not _is_explored(row):
			continue
		var name_base: String = "Interface\\WorldMap\\%s\\%s" % [
			file, _overlays.get_string(row, "TextureName"),
		]
		var width: int = _overlays.get_uint(row, "TextureWidth")
		var height: int = _overlays.get_uint(row, "TextureHeight")
		var offset: Vector2 = Vector2(
			_overlays.get_uint(row, "OffsetX"), _overlays.get_uint(row, "OffsetY"),
		)
		var wide: int = ceili(width / TILE_SIZE)
		var tall: int = ceili(height / TILE_SIZE)
		for j: int in tall:
			for k: int in wide:
				var piece_width: float = TILE_SIZE if k < wide - 1 else fposmod(width, TILE_SIZE)
				var piece_height: float = TILE_SIZE if j < tall - 1 else fposmod(height, TILE_SIZE)
				piece_width = TILE_SIZE if piece_width == 0.0 else piece_width
				piece_height = TILE_SIZE if piece_height == 0.0 else piece_height
				var sheet: WowTexture = WowTexture.new()
				sheet.file = "%s%d.blp" % [name_base, j * wide + k + 1]
				var atlas: AtlasTexture = AtlasTexture.new()
				atlas.atlas = sheet
				atlas.region = Rect2(0.0, 0.0, piece_width, piece_height)
				var piece: TextureRect = TextureRect.new()
				piece.texture = atlas
				piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
				piece.position = offset + Vector2(k, j) * TILE_SIZE
				piece.size = Vector2(piece_width, piece_height)
				_detail.add_child(piece)
				_overlay_pieces.append(piece)


# mWoW's marker layer: AreaPOI landmarks, flight masters, and quest givers in view.
func _update_markers() -> void:
	for node: Control in _markers:
		node.queue_free()
	for label: Label in _labels:
		label.queue_free()
	_markers.clear()
	_labels.clear()
	if _shown < 0:
		return
	var map_id: int = _areas.get_uint(_areas.find(_shown), "MapID")
	var zone_level: bool = not _is_continent(_shown)
	if WowAssets.interface.is_on(&"show_map_pois"):
		_add_pois(map_id, zone_level)
	var alliance: bool = _player_race() in ALLIANCE_RACES
	for node: int in TaxiNodes.all_on_map(map_id):
		if not TaxiNodes.serves(node, alliance):
			continue
		var known: bool = TaxiNodes.is_known(node)
		var hint: String = WowStrings.get_text("TAXI_FLIGHT_MASTER", "Flight Master")
		_add_marker(
			map_id, TaxiNodes.position(node),
			WorldMapMarker.Kind.FLIGHT_KNOWN if known else WorldMapMarker.Kind.FLIGHT_UNKNOWN,
			TaxiNodes.node_name(node), "(%s)" % hint if known else "(%s, not yet discovered)" % hint,
		)
	if map_id == _corpse_map:
		_add_marker(
			map_id, _corpse_position, WorldMapMarker.Kind.CORPSE,
			WowStrings.get_text("CORPSE_TOOLTIP", "Your corpse"), "",
		)
	var session: WowSession = WowClient.session
	var battlegrounds: Battlegrounds = WowClient.battlegrounds
	if map_id == _player_map and battlegrounds.in_battle():
		for guid: int in battlegrounds.positions:
			var at: Vector2 = battlegrounds.positions[guid]
			var carrier: bool = guid == battlegrounds.flag_carrier
			_add_marker(
				map_id, Vector3(at.x, at.y, 0.0),
				WorldMapMarker.Kind.FLAG_CARRIER if carrier else WorldMapMarker.Kind.TEAM_MATE,
				session.get_object_name(guid), "",
			)
	if map_id == _player_map:
		for guid: int in NpcDialog.quest_givers_offering():
			_add_marker(
				map_id, session.get_object_position(guid), WorldMapMarker.Kind.QUEST,
				session.get_object_name(guid), "",
			)


# AreaPOI landmarks: inns, towns and the like, which the interface options can turn off.
func _add_pois(map_id: int, zone_level: bool) -> void:
	for row: int in _pois.row_count():
		if _pois.get_uint(row, "MapID") != map_id:
			continue
		var importance: int = _pois.get_uint(row, "Importance")
		if not zone_level and importance < LABELLED_IMPORTANCE:
			continue
		var at: Vector3 = Vector3(_pois.get_float(row, "X"), _pois.get_float(row, "Y"), 0.0)
		var kind: WorldMapMarker.Kind = WorldMapMarker.Kind.MAJOR_POI \
		if importance >= MAJOR_IMPORTANCE else WorldMapMarker.Kind.POI
		var poi_name: String = _pois.get_string(row, "Name")
		var marker: WorldMapMarker = _add_marker(
			map_id, at, kind, poi_name, _pois.get_string(row, "Description"),
		)
		if marker and zone_level and importance >= LABELLED_IMPORTANCE:
			_add_label(marker, poi_name)


func _add_marker(
	map_id: int, at: Vector3, kind: WorldMapMarker.Kind, title: String, description: String,
) -> WorldMapMarker:
	var point: Vector2 = _map_point(map_id, at)
	if point.x < 0.0 or point.x > 1.0 or point.y < 0.0 or point.y > 1.0:
		return null
	var marker: WorldMapMarker = MARKER.instantiate()
	marker.kind = kind
	marker.title = title
	marker.description = description
	_button.add_child(marker)
	marker.position = point * _button.size - marker.size / 2.0
	marker.mouse_entered.connect(_on_marker_entered.bind(marker))
	marker.mouse_exited.connect(_on_marker_exited.bind(marker))
	_markers.append(marker)
	return marker


func _add_label(marker: Control, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = &"GameFontHighlightSmall"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(label)
	label.position = marker.position + LABEL_OFFSET
	_labels.append(label)


# A wire position on the shown map, 0 to 1 from its west and north edges; off it for other maps.
func _map_point(map_id: int, at: Vector3) -> Vector2:
	var row: int = _areas.find(_shown)
	if row < 0 or _areas.get_uint(row, "MapID") != map_id:
		return Vector2(-1.0, -1.0)
	var left: float = _areas.get_float(row, "LocLeft")
	var right: float = _areas.get_float(row, "LocRight")
	var top: float = _areas.get_float(row, "LocTop")
	var bottom: float = _areas.get_float(row, "LocBottom")
	return Vector2((left - at.y) / (left - right), (top - at.x) / (top - bottom))


func _is_continent(area_row_id: int) -> bool:
	var row: int = _areas.find(area_row_id)
	return row >= 0 and _areas.get_uint(row, "AreaID") == 0


func _continent_of(map_id: int) -> int:
	for row: int in _areas.row_count():
		if _areas.get_uint(row, "MapID") == map_id and _areas.get_uint(row, "AreaID") == 0:
			return _areas.get_uint(row, "ID")
	return -1


# UpdateMapHighlight: the smallest zone of the shown continent under a map point.
func _zone_at(point: Vector2) -> int:
	var continent: int = _areas.find(_shown)
	var map_id: int = _areas.get_uint(continent, "MapID")
	var left: float = _areas.get_float(continent, "LocLeft")
	var right: float = _areas.get_float(continent, "LocRight")
	var top: float = _areas.get_float(continent, "LocTop")
	var bottom: float = _areas.get_float(continent, "LocBottom")
	var y: float = left - point.x * (left - right)
	var x: float = top - point.y * (top - bottom)
	var best: int = -1
	var best_size: float = INF
	for row: int in _areas.row_count():
		if _areas.get_uint(row, "MapID") != map_id or _areas.get_uint(row, "AreaID") == 0:
			continue
		var zone_left: float = _areas.get_float(row, "LocLeft")
		var zone_right: float = _areas.get_float(row, "LocRight")
		var zone_top: float = _areas.get_float(row, "LocTop")
		var zone_bottom: float = _areas.get_float(row, "LocBottom")
		if y <= zone_left and y >= zone_right and x <= zone_top and x >= zone_bottom:
			var zone_size: float = (zone_left - zone_right) * (zone_top - zone_bottom)
			if zone_size < best_size:
				best_size = zone_size
				best = _areas.get_uint(row, "ID")
	return best


# The player's zone map, found by walking the area up to its zone, or else their continent.
func _player_zone() -> int:
	var area: int = _player_area
	while area != 0:
		for row: int in _areas.row_count():
			if _areas.get_uint(row, "AreaID") == area:
				return _areas.get_uint(row, "ID")
		var area_row: int = _area_table.find(area)
		area = _area_table.get_uint(area_row, "ParentAreaNum") if area_row >= 0 else 0
	return _continent_of(_player_map)


# Overlays show once any of their areas has been discovered, per PLAYER_EXPLORED_ZONES.
func _is_explored(overlay_row: int) -> bool:
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	var first: int = session.field_index("PLAYER_EXPLORED_ZONES_1")
	for i: int in 4:
		var area: int = _overlays.get_uint(overlay_row, "AreaID%d" % i)
		var area_row: int = _area_table.find(area) if area else -1
		if area_row < 0:
			continue
		var bit: int = _area_table.get_uint(area_row, "ExploreFlag")
		if bit >> 5 < EXPLORED_WORDS and session.get_field(guid, first + (bit >> 5)) & (1 << (bit & 31)):
			return true
	return false


func _player_race() -> int:
	var session: WowSession = WowClient.session
	return session.get_field(session.get_player_guid(), "UNIT_FIELD_BYTES_0") & 0xFF


# WorldMapZoomOutButton_OnClick: zone to continent to the world.
func _zoom_out() -> void:
	if _shown < 0:
		return
	var row: int = _areas.find(_shown)
	show_area(-1 if _is_continent(_shown) else _continent_of(_areas.get_uint(row, "MapID")))


# WorldMapButton_OnClick: left clicks go a level in, right clicks back out.
func _on_map_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	if click.button_index == MOUSE_BUTTON_RIGHT:
		_zoom_out()
		return
	if click.button_index != MOUSE_BUTTON_LEFT:
		return
	var point: Vector2 = click.position / _button.size
	if _shown < 0:
		show_area(_continent_of(WORLD_CONTINENTS[0 if point.x < 0.5 else 1]))
	elif _is_continent(_shown):
		var zone: int = _zone_at(point)
		if zone >= 0:
			show_area(zone)


func _on_marker_entered(marker: WorldMapMarker) -> void:
	if GameTooltip.current:
		GameTooltip.current.set_text(marker, marker.title, marker.description)


func _on_marker_exited(marker: WorldMapMarker) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(marker)


# WorldMapFrame_OnShow: the map opens on the player's zone.
func _on_visibility_changed() -> void:
	if visible:
		show_area(_player_zone())
