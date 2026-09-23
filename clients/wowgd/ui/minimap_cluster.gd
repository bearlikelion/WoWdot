class_name MinimapCluster
extends Control

# GetZonePVPInfo colours for the zone name above the minimap.
const FRIENDLY: Color = Color(0.1, 1.0, 0.1)
const HOSTILE: Color = Color(1.0, 0.1, 0.1)
const CONTESTED: Color = Color(1.0, 0.7, 0.0)

var _tracking_spell: int = 0

@onready var _view: MinimapView = %Minimap
@onready var _zone_text: Label = %MinimapZoneText
@onready var _zoom_in: BaseButton = %MinimapZoomIn
@onready var _zoom_out: BaseButton = %MinimapZoomOut
@onready var _toggle: BaseButton = %MinimapToggleButton
@onready var _game_time: TextureRect = %GameTimeTexture
@onready var _tracking: Control = %MiniMapTrackingFrame
@onready var _tracking_icon: TextureRect = %MiniMapTrackingIcon


func _ready() -> void:
	# The zone name is tinted per PvP status, so it starts from the white font.
	_zone_text.theme_type_variation = &"GameFontHighlight"
	_zoom_in.pressed.connect(func() -> void: _view.zoom += 1)
	_zoom_out.pressed.connect(func() -> void: _view.zoom -= 1)
	_toggle.pressed.connect(_toggle_minimap)
	_view.zoom_changed.connect(_on_zoom_changed)
	_on_zoom_changed(_view.zoom)
	var indicator: AtlasTexture = AtlasTexture.new()
	indicator.atlas = _game_time.texture
	_game_time.texture = indicator
	WowClient.session.packet_received.connect(_on_packet_received)
	WowClient.session.send_packet("MSG_QUERY_NEXT_MAIL_TIME", PackedByteArray())
	WowClient.session.object_updated.connect(_on_object_updated)
	_tracking.gui_input.connect(_on_tracking_input)
	_tracking.mouse_entered.connect(_on_tracking_entered)
	_tracking.mouse_exited.connect(_on_tracking_exited)


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


# The reply is seconds until mail arrives: zero or more means some waits, negative means none.
func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	match opcode:
		"MSG_QUERY_NEXT_MAIL_TIME":
			%MiniMapMailFrame.visible = payload.size() >= 4 and payload.decode_float(0) >= 0.0
		"SMSG_RECEIVED_MAIL":
			%MiniMapMailFrame.show()
		"SMSG_MAIL_LIST_RESULT":
			WowClient.session.send_packet("MSG_QUERY_NEXT_MAIL_TIME", PackedByteArray())


# ToggleMinimap: closing and opening each have their own sound.
func _toggle_minimap() -> void:
	_view.visible = not _view.visible
	WowAssets.audio.play_sound("igMiniMapOpen" if _view.visible else "igMiniMapClose")


# PLAYER_AURAS_CHANGED: the frame shows the icon of whichever tracking aura is up.
func _on_object_updated(guid: int) -> void:
	var session: WowSession = WowClient.session
	if guid != session.get_player_guid():
		return
	_tracking_spell = 0
	for aura: Dictionary in UnitAuras.read(session, guid):
		if WowAssets.spells.is_tracking(aura["spell"]):
			_tracking_spell = aura["spell"]
	_tracking.visible = _tracking_spell != 0
	if _tracking.visible:
		_tracking_icon.texture = WowAssets.spells.icon(_tracking_spell)


# CancelTrackingBuff on a right click.
func _on_tracking_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click and not click.pressed and click.button_index == MOUSE_BUTTON_RIGHT \
	and _tracking_spell != 0:
		WowClient.session.cancel_aura(_tracking_spell)


func _on_tracking_entered() -> void:
	if _tracking_spell != 0 and GameTooltip.current:
		GameTooltip.current.set_spell(
			_tracking, _tracking_spell, GameTooltip.TooltipAnchor.BOTTOM_LEFT
		)


func _on_tracking_exited() -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(_tracking)


func _on_zoom_changed(zoom: int) -> void:
	_zoom_out.disabled = zoom == 0
	_zoom_in.disabled = zoom == MinimapView.ZOOM_DIAMETERS.size() - 1
