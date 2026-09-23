class_name VehicleMenuBar
extends Control

const SKINS_PATH: String = "res://data/wotlk/vehicle_skins.json"
# Every AzerothCore vehicle probed has LocomotionType 0, which falls back to this skin.
const SKIN: String = "Mechanical"
const BUTTONS: int = 6
const POINTS: Dictionary[String, Vector2] = {
	"TOPLEFT": Vector2(0.0, 0.0), "TOP": Vector2(0.5, 0.0), "TOPRIGHT": Vector2(1.0, 0.0),
	"LEFT": Vector2(0.0, 0.5), "CENTER": Vector2(0.5, 0.5), "RIGHT": Vector2(1.0, 0.5),
	"BOTTOMLEFT": Vector2(0.0, 1.0), "BOTTOM": Vector2(0.5, 1.0), "BOTTOMRIGHT": Vector2(1.0, 1.0),
}
# The pitch slider sends aim angles this client does not drive yet.
const PITCH_VISIBLE: bool = false

var _buttons: Array[ActionButton] = []


func _ready() -> void:
	var skin: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SKINS_PATH))[SKIN]
	_apply_skin(skin)
	# The art frame sits at a lower frame level than the buttons it surrounds.
	move_child(%VehicleMenuBarArtFrame, 0)
	for i: int in BUTTONS:
		var button: ActionButton = get_node("%%VehicleMenuBarActionButton%d" % (i + 1))
		button.pressed.connect(_on_button_pressed.bind(i))
		_buttons.append(button)
	for bar: TextureProgressBar in [%VehicleMenuBarHealthBar, %VehicleMenuBarPowerBar]:
		bar.fill_mode = TextureProgressBar.FILL_BOTTOM_TO_TOP
		# TextStatusBar keeps its numbers hidden until the cursor is over the bar.
		var text: Label = get_node("%" + bar.name + "Text")
		text.hide()
		bar.mouse_filter = MOUSE_FILTER_PASS
		bar.mouse_entered.connect(text.show)
		bar.mouse_exited.connect(text.hide)
	%VehicleMenuBarLeaveButton.pressed.connect(WowClient.vehicle.leave)
	WowClient.vehicle.changed.connect(refresh)
	WowClient.pet.changed.connect(refresh)
	WowClient.session.object_updated.connect(_on_object_updated)
	refresh()


func refresh() -> void:
	var driving: int = WowClient.vehicle.driving
	visible = driving != 0
	if not visible:
		return
	var pet: Pet = WowClient.pet
	for i: int in BUTTONS:
		var packed: int = pet.actions[i] if pet.guid == driving and i < pet.actions.size() else 0
		_buttons[i].stance_spell = pet.spell_of(packed)
		_buttons[i].visible = pet.spell_of(packed) != 0
	_update_bars()


# VehicleMenuBar_SetSkin: numbered entries fill the art frame's layers, named ones place the parts.
func _apply_skin(skin: Dictionary) -> void:
	var overall: Dictionary = skin["Overall"]
	var width: float = overall["yesPitchWidth" if PITCH_VISIBLE else "noPitchWidth"]
	offset_left = -width / 2.0
	offset_right = width / 2.0
	var used: Dictionary[String, int] = {}
	for layer: Dictionary in skin["layers"]:
		if _hidden(layer):
			continue
		used[layer["layer"]] = used.get(layer["layer"], 0) + 1
		var rect: TextureRect = get_node(
			"%%VehicleMenuBarArtFrame%s%d" % [layer["layer"], used[layer["layer"]]]
		)
		var size_px: Vector2 = Vector2(layer["width"], layer["height"])
		_set_texture(rect, layer["texture"], layer["texCoord"], size_px, layer.get("tile", false))
		_place(rect, layer, size_px)
	for frame_name: String in skin:
		if frame_name == "Overall" or frame_name == "layers":
			continue
		var part: Dictionary = skin[frame_name]
		var frame: Control = get_node("%VehicleMenuBar" + frame_name)
		var size_px: Vector2 = frame.size
		if part.has("height"):
			size_px = Vector2(part["width"], part["height"])
		if part.has("normalTexture"):
			var normal: TextureRect = frame.get_node("NormalTexture")
			var pushed: TextureRect = frame.get_node("PushedTexture")
			_set_texture(normal, part["normalTexture"], part["normalTexCoord"])
			_set_texture(pushed, part["pushedTexture"], part["pushedTexCoord"])
			for state: String in ["NormalTexture", "PushedTexture", "HighlightTexture"]:
				(frame.get_node(state) as Control).set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		if part.has("texture"):
			_set_texture(frame as TextureRect, part["texture"], part["texCoord"])
		if part.has("vertexColor"):
			var color: Array = part["vertexColor"]
			frame.self_modulate = Color(color[0], color[1], color[2])
		if part.has("point"):
			_place(frame, part, size_px)
		frame.visible = not _hidden(part)


static func _hidden(part: Dictionary) -> bool:
	return int(part.get("pitchHidden", 0)) & (int(PITCH_VISIBLE) + 1) != 0


# SetPoint with WoW's upward y, the control's point pinned to its parent's relative point.
static func _place(control: Control, part: Dictionary, size_px: Vector2) -> void:
	var point: Vector2 = POINTS[part["point"]]
	var relative: Vector2 = POINTS[part.get("relativePoint", part["point"])]
	var top_left: Vector2 = \
			Vector2(part.get("xOfs", 0.0), -part.get("yOfs", 0.0)) - point * size_px
	control.anchor_left = relative.x
	control.anchor_right = relative.x
	control.anchor_top = relative.y
	control.anchor_bottom = relative.y
	control.offset_left = top_left.x
	control.offset_top = top_left.y
	control.offset_right = top_left.x + size_px.x
	control.offset_bottom = top_left.y + size_px.y


# SetTexCoord; a tiled texture repeats across coordinates past 1, scaled to the rect's height.
static func _set_texture(
	rect: TextureRect,
	path: String,
	coords: Array,
	size_px: Vector2 = Vector2.ZERO,
	tile: bool = false,
) -> void:
	var sheet: WowTexture = WowTexture.new()
	sheet.file = path + ".blp"
	var sheet_size: Vector2 = sheet.get_size()
	var left: float = minf(coords[0], coords[1])
	var top: float = minf(coords[2], coords[3])
	var span: Vector2 = Vector2(absf(coords[1] - coords[0]), absf(coords[3] - coords[2]))
	rect.flip_h = coords[0] > coords[1]
	rect.flip_v = coords[2] > coords[3]
	if tile:
		var region: Rect2i = Rect2i(
			0, roundi(top * sheet_size.y), int(sheet_size.x), roundi(span.y * sheet_size.y)
		)
		var image: Image = sheet.get_image().get_region(region)
		image.resize(roundi(size_px.x / span.x), roundi(size_px.y))
		rect.texture = ImageTexture.create_from_image(image)
		rect.stretch_mode = TextureRect.STRETCH_TILE
		return
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(Vector2(left, top) * sheet_size, span * sheet_size)
	rect.texture = atlas


func _update_bars() -> void:
	var session: WowSession = WowClient.session
	var guid: int = WowClient.vehicle.driving
	var health: int = session.get_field(guid, "UNIT_FIELD_HEALTH")
	var max_health: int = maxi(session.get_field(guid, "UNIT_FIELD_MAXHEALTH"), 1)
	var health_bar: TextureProgressBar = %VehicleMenuBarHealthBar
	health_bar.max_value = max_health
	health_bar.value = health
	health_bar.tint_progress = UnitFrame.HEALTH_COLOR
	(%VehicleMenuBarHealthBarText as Label).text = "%d / %d" % [health, max_health]
	var power_type: UnitFrame.PowerType = \
			((session.get_field(guid, "UNIT_FIELD_BYTES_0") >> 24) & 0xFF) as UnitFrame.PowerType
	var power: int = session.get_field(guid, session.field_index("UNIT_FIELD_POWER1") + power_type)
	var max_power: int = \
			session.get_field(guid, session.field_index("UNIT_FIELD_MAXPOWER1") + power_type)
	var power_bar: TextureProgressBar = %VehicleMenuBarPowerBar
	power_bar.visible = max_power > 0
	power_bar.max_value = maxi(max_power, 1)
	power_bar.value = power
	power_bar.tint_progress = UnitFrame.POWER_COLORS.get(power_type, UnitFrame.HEALTH_COLOR)
	(%VehicleMenuBarPowerBarText as Label).text = "%d / %d" % [power, max_power]


func _on_object_updated(guid: int) -> void:
	if visible and guid == WowClient.vehicle.driving:
		_update_bars()


func _on_button_pressed(index: int) -> void:
	var pet: Pet = WowClient.pet
	if index < pet.actions.size():
		pet.send_action(pet.actions[index])
