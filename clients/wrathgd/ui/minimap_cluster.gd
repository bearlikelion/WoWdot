class_name MinimapCluster
extends Control

signal lfd_toggled
signal calendar_toggled

# GetZonePVPInfo colours for the zone name above the minimap.
const FRIENDLY: Color = Color(0.1, 1.0, 0.1)
const HOSTILE: Color = Color(1.0, 0.1, 0.1)
const CONTESTED: Color = Color(1.0, 0.7, 0.0)

@onready var _view: MinimapView = %Minimap
@onready var _zone_text: Label = %MinimapZoneText
@onready var _zoom_in: BaseButton = %MinimapZoomIn
@onready var _zoom_out: BaseButton = %MinimapZoomOut
@onready var _game_time: TextureRect = %GameTimeTexture


func _ready() -> void:
	# The zone name is tinted per PvP status, so it starts from the white font.
	_zone_text.theme_type_variation = &"GameFontHighlight"
	_zoom_in.pressed.connect(func() -> void: _view.zoom += 1)
	_zoom_out.pressed.connect(func() -> void: _view.zoom -= 1)
	_view.zoom_changed.connect(_on_zoom_changed)
	_on_zoom_changed(_view.zoom)
	var indicator: AtlasTexture = AtlasTexture.new()
	indicator.atlas = _game_time.texture
	_game_time.texture = indicator
	%GameTimeFrame.pressed.connect(calendar_toggled.emit)
	LFGArt.eye(%MiniMapLFGFrameIconTexture)
	%MiniMapLFGFrameDropDown.hide()
	%MiniMapLFGFrame.pressed.connect(lfd_toggled.emit)
	%MiniMapLFGFrame.mouse_entered.connect(_on_lfd_hovered)
	%MiniMapLFGFrame.mouse_exited.connect(func() -> void:
		if GameTooltip.current:
			GameTooltip.current.hide_for(%MiniMapLFGFrame))
	WowClient.dungeon_finder.changed.connect(func() -> void:
		%MiniMapLFGFrame.visible = WowClient.dungeon_finder.state != DungeonFinder.State.NONE)
	WowClient.session.packet_received.connect(_on_packet_received)
	WowClient.session.send_packet("MSG_QUERY_NEXT_MAIL_TIME", PackedByteArray())


# GameTimeFrame_Update: the day face is the left half of the texture, the night face the right.
func _process(_delta: float) -> void:
	var indicator: AtlasTexture = _game_time.texture
	var half: Vector2 = indicator.atlas.get_size() * Vector2(0.5, 1.0)
	var left: float = half.x if WowClient.clock.is_night() else 0.0
	indicator.region = Rect2(Vector2(left, 0.0), half)


func show_corpse(wow_position: Vector3, map_id: int) -> void:
	%Minimap.show_corpse(wow_position, map_id)


func show_location(map_dir: String, wow_position: Vector3, facing: float) -> void:
	_view.show_location(map_dir, wow_position, facing)


func show_area(area_id: int, player_race: int) -> void:
	_zone_text.text = AreaInfo.area_name(area_id)
	var faction: AreaInfo.FactionGroup = AreaInfo.faction_group(area_id)
	if faction == AreaInfo.FactionGroup.NONE:
		_zone_text.self_modulate = CONTESTED
	elif faction == AreaInfo.player_group(player_race):
		_zone_text.self_modulate = FRIENDLY
	else:
		_zone_text.self_modulate = HOSTILE


# LFDSearchStatus in brief: the dungeon queued for and the average wait.
func _on_lfd_hovered() -> void:
	if GameTooltip.current == null:
		return
	var finder: DungeonFinder = WowClient.dungeon_finder
	var dungeon: String = finder.dungeon_name(finder.queued_dungeons[0]) \
			if not finder.queued_dungeons.is_empty() else ""
	var wait: int = finder.queue_status.get("average_wait", -1)
	var wait_text: String = WowStrings.get_text("TIME_UNKNOWN") if wait < 0 \
			else "%d:%02d" % [floori(wait / 60.0), wait % 60]
	var average: String = WowStrings.get_text("LFG_STATISTIC_AVERAGE_WAIT").replace("%s", wait_text)
	GameTooltip.current.set_text(%MiniMapLFGFrame, WowStrings.get_text("LOOKING_FOR_DUNGEON"),
			dungeon + "\n" + average)


# The reply is seconds until mail arrives: zero or more means some waits, negative means none.
func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	match opcode:
		"MSG_QUERY_NEXT_MAIL_TIME":
			%MiniMapMailFrame.visible = payload.size() >= 4 and payload.decode_float(0) >= 0.0
		"SMSG_RECEIVED_MAIL":
			%MiniMapMailFrame.show()
		"SMSG_MAIL_LIST_RESULT":
			WowClient.session.send_packet("MSG_QUERY_NEXT_MAIL_TIME", PackedByteArray())


func _on_zoom_changed(zoom: int) -> void:
	_zoom_out.disabled = zoom == 0
	_zoom_in.disabled = zoom == MinimapView.ZOOM_DIAMETERS.size() - 1
