class_name GlyphFrame
extends Control

enum GlyphType { MAJOR, MINOR }

const SOCKETS: int = 6
const FRAME_ART: String = "Interface\\Spellbook\\UI-GlyphFrame.blp"
const LOCKED_ART: String = "Interface\\Spellbook\\UI-GlyphFrame-Locked.blp"
const RUNE_ART: String = "Interface\\Spellbook\\UI-Glyph-Rune1.blp"
const FRAME_ART_SIZE: float = 512.0
const LOCKED_ART_SIZE: float = 128.0
const COLORS: Dictionary[GlyphType, Color] = {
	GlyphType.MAJOR: Color(1.0, 0.25, 0.0),
	GlyphType.MINOR: Color(0.0, 0.25, 1.0),
}
# GLYPH_SLOTS as left, right, top, bottom on UI-GlyphFrame; 0 is an empty socket's background.
const SOCKET_ART: Array[Vector4] = [
	Vector4(0.78125, 0.91015625, 0.69921875, 0.828125),
	Vector4(0.0, 0.12890625, 0.87109375, 1.0),
	Vector4(0.130859375, 0.259765625, 0.87109375, 1.0),
	Vector4(0.392578125, 0.521484375, 0.87109375, 1.0),
	Vector4(0.5234375, 0.65234375, 0.87109375, 1.0),
	Vector4(0.26171875, 0.390625, 0.87109375, 1.0),
	Vector4(0.654296875, 0.783203125, 0.87109375, 1.0),
]
# GlyphFrameGlyph_SetGlyphType: each part's size and art, major then minor.
const SETTING: Dictionary[GlyphType, Array] = {
	GlyphType.MAJOR: [108.0, Vector4(0.740234375, 0.953125, 0.484375, 0.697265625)],
	GlyphType.MINOR: [86.0, Vector4(0.765625, 0.927734375, 0.15625, 0.31640625)],
}
const RING: Dictionary[GlyphType, Array] = {
	GlyphType.MAJOR: [82.0, Vector4(0.767578125, 0.92578125, 0.32421875, 0.482421875)],
	GlyphType.MINOR: [62.0, Vector4(0.787109375, 0.908203125, 0.033203125, 0.154296875)],
}
const BACKGROUND_SIZE: Dictionary[GlyphType, float] = {
	GlyphType.MAJOR: 70.0, GlyphType.MINOR: 64.0,
}

var _glyphs: WowDBC
var _slots: WowDBC
var _spells: Array[int] = []


func _ready() -> void:
	_glyphs = WowDBC.open(WowAssets.archive, "GlyphProperties")
	_slots = WowDBC.open(WowAssets.archive, "GlyphSlot")
	_spells.resize(SOCKETS)
	for socket: int in SOCKETS:
		var button: BaseButton = _socket(socket)
		button.pressed.connect(_on_socket_pressed.bind(socket))
		button.gui_input.connect(_on_socket_input.bind(socket))
		button.mouse_entered.connect(_on_socket_hovered.bind(socket))
		button.mouse_exited.connect(_on_socket_left.bind(socket))
	WowClient.session.object_updated.connect(_on_object_updated)
	visibility_changed.connect(refresh)


# GlyphFrameGlyph_UpdateSlot for each socket: locked, empty, or holding a glyph.
func refresh() -> void:
	if not is_visible_in_tree():
		return
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	var enabled: int = session.get_field(guid, "PLAYER_GLYPHS_ENABLED")
	var first_slot: int = session.field_index("PLAYER_FIELD_GLYPH_SLOTS_1")
	var first_glyph: int = session.field_index("PLAYER_FIELD_GLYPHS_1")
	for socket: int in SOCKETS:
		var slot_row: int = _slots.find(session.get_field(guid, first_slot + socket))
		var glyph_row: int = _glyphs.find(session.get_field(guid, first_glyph + socket))
		var type: GlyphType = GlyphType.MINOR if slot_row >= 0 \
				and _slots.get_uint(slot_row, "TypeFlags") == 1 else GlyphType.MAJOR
		_spells[socket] = _glyphs.get_uint(glyph_row, "SpellId") if glyph_row >= 0 else 0
		_show_socket(socket, type, slot_row >= 0 and enabled & (1 << socket) != 0, glyph_row)


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid():
		refresh()


func _show_socket(socket: int, type: GlyphType, unlocked: bool, glyph_row: int) -> void:
	var prefix: String = "%%GlyphFrameGlyph%d" % (socket + 1)
	var setting: TextureRect = get_node(prefix + "Setting")
	var background: TextureRect = get_node(prefix + "Background")
	var glyph: TextureRect = get_node(prefix + "Glyph")
	var ring: TextureRect = get_node(prefix + "Ring")
	var shine: CanvasItem = get_node(prefix + "Shine")
	var highlight: TextureRect = get_node(prefix + "Highlight")
	_art(highlight, FRAME_ART, FRAME_ART_SIZE, SETTING[type][1], SETTING[type][0])
	highlight.hide()
	if not unlocked:
		_art(setting, LOCKED_ART, LOCKED_ART_SIZE, Vector4(0.1, 0.9, 0.1, 0.9), SETTING[type][0])
		for part: CanvasItem in [background, glyph, ring, shine]:
			part.hide()
		return
	_art(setting, FRAME_ART, FRAME_ART_SIZE, SETTING[type][1], SETTING[type][0])
	_art(ring, FRAME_ART, FRAME_ART_SIZE, RING[type][1], RING[type][0])
	var art: Vector4 = SOCKET_ART[socket + 1 if glyph_row >= 0 else 0]
	_art(background, FRAME_ART, FRAME_ART_SIZE, art, BACKGROUND_SIZE[type])
	for part: CanvasItem in [background, ring, shine]:
		part.show()
	glyph.visible = glyph_row >= 0
	if glyph_row >= 0:
		var icon_id: int = _glyphs.get_uint(glyph_row, "SpellIconID")
		var icon: String = WowAssets.spells.icon_path(icon_id)
		var texture: WowTexture = WowTexture.new()
		texture.file = icon + ".blp" if not icon.is_empty() else RUNE_ART
		glyph.texture = texture
		glyph.self_modulate = COLORS[type]


# SetTexCoord and SetWidth together: the part keeps its centre in the socket.
func _art(rect: TextureRect, file: String, art_size: float, coords: Vector4, side: float) -> void:
	var texture: WowTexture = WowTexture.new()
	texture.file = file
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(
		coords.x * art_size, coords.z * art_size,
		(coords.y - coords.x) * art_size, (coords.w - coords.z) * art_size,
	)
	rect.texture = atlas
	var centre: Vector2 = rect.position + rect.size / 2.0
	rect.size = Vector2(side, side)
	rect.position = centre - rect.size / 2.0


func _socket(socket: int) -> BaseButton:
	return get_node("%%GlyphFrameGlyph%d" % (socket + 1))


# A glyph in hand goes into the socket clicked.
func _on_socket_pressed(socket: int) -> void:
	if WowClient.targeting.is_glyph():
		WowClient.targeting.place_glyph(socket)


# Shift right-click takes a glyph out.
func _on_socket_input(event: InputEvent, socket: int) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_RIGHT or click.pressed:
		return
	if click.shift_pressed and _spells[socket] != 0:
		var payload: PackedByteArray = []
		payload.resize(4)
		payload.encode_u32(0, socket)
		WowClient.session.send_packet("CMSG_REMOVE_GLYPH", payload)


func _on_socket_hovered(socket: int) -> void:
	var prefix: String = "%%GlyphFrameGlyph%d" % (socket + 1)
	(get_node(prefix + "Highlight") as CanvasItem).visible = \
			(get_node(prefix + "Background") as CanvasItem).visible
	if _spells[socket] != 0 and GameTooltip.current:
		GameTooltip.current.set_spell(_socket(socket), _spells[socket])


func _on_socket_left(socket: int) -> void:
	(get_node("%%GlyphFrameGlyph%dHighlight" % (socket + 1)) as CanvasItem).hide()
	if GameTooltip.current:
		GameTooltip.current.hide_for(_socket(socket))
