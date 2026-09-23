@tool
class_name UnitFrame
extends WowButton

signal unit_selected(guid: int)
signal unit_menu_requested(guid: int)

enum PowerType { MANA, RAGE, FOCUS, ENERGY, HAPPINESS }

const PORTRAIT: PackedScene = preload("res://ui/unit_portrait.tscn")
const PORTRAIT_MASK: Shader = preload("res://ui/portrait.gdshader")
# ManaBarColor from UnitFrame.lua.
const POWER_COLORS: Dictionary[PowerType, Color] = {
	PowerType.MANA: Color(0.0, 0.0, 1.0),
	PowerType.RAGE: Color(1.0, 0.0, 0.0),
	PowerType.FOCUS: Color(1.0, 0.5, 0.25),
	PowerType.ENERGY: Color(1.0, 1.0, 0.0),
	PowerType.HAPPINESS: Color(0.0, 1.0, 1.0),
}
const HEALTH_COLOR: Color = Color(0.0, 1.0, 0.0)
# Rage is stored at ten times the value the bar shows.
const RAGE_SCALE: int = 10
const UNIT_FLAG_PVP: int = 0x1000
const PLAYER_FLAGS_FFA_PVP: int = 0x80
const FFA_PVP_ICON: String = "Interface\\TargetingFrame\\UI-PVP-FFA.blp"
const PVP_ICONS: Dictionary[AreaInfo.FactionGroup, String] = {
	AreaInfo.FactionGroup.ALLIANCE: "Interface\\TargetingFrame\\UI-PVP-Alliance.blp",
	AreaInfo.FactionGroup.HORDE: "Interface\\TargetingFrame\\UI-PVP-Horde.blp",
}

var guid: int = 0

static var _pvp_textures: Dictionary[String, WowTexture] = {}

var _display: int = 0
# Set by each frame's _ready from its own scene's nodes before calling super().
var _name_label: Label
var _level_label: Label
var _health_bar: TextureProgressBar
var _power_bar: TextureProgressBar
var _health_text: Label
var _power_text: Label
var _portrait_rect: TextureRect
var _portrait: UnitPortrait


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	pressed.connect(func() -> void: unit_selected.emit(guid))
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	var session: WowSession = WowClient.session
	session.object_updated.connect(_on_object_updated)
	session.name_received.connect(_on_name_received)
	session.objects_destroyed.connect(_on_objects_destroyed)
	_portrait = PORTRAIT.instantiate()
	add_child(_portrait)
	if _portrait_rect:
		var mask: ShaderMaterial = ShaderMaterial.new()
		mask.shader = PORTRAIT_MASK
		_portrait_rect.material = mask
		_portrait_rect.texture = _portrait.get_texture()
	for bar: TextureProgressBar in [_health_bar, _power_bar]:
		bar.mouse_filter = Control.MOUSE_FILTER_PASS
		bar.mouse_entered.connect(_show_bar_text.bind(true))
		bar.mouse_exited.connect(_show_bar_text.bind(false))
	_show_bar_text(false)
	WowAssets.interface.changed.connect(func() -> void: _show_bar_text(false))
	show_unit(guid)


func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		unit_menu_requested.emit(guid)


# A guid of 0, or one the session no longer knows, hides the frame.
# TargetFrame_CheckFaction: a free-for-all player shows that icon, else a flagged one its faction's.
static func pvp_texture(unit: int) -> Texture2D:
	var session: WowSession = WowClient.session
	if session.get_object_type(unit) != Entities.ObjectType.PLAYER:
		return null
	var path: String = ""
	if session.get_field(unit, "PLAYER_FLAGS") & PLAYER_FLAGS_FFA_PVP:
		path = FFA_PVP_ICON
	elif session.get_field(unit, "UNIT_FIELD_FLAGS") & UNIT_FLAG_PVP:
		var race: int = session.get_field(unit, "UNIT_FIELD_BYTES_0") & 0xFF
		path = PVP_ICONS[AreaInfo.player_group(race)]
	if path.is_empty():
		return null
	if not _pvp_textures.has(path):
		var texture: WowTexture = WowTexture.new()
		texture.file = path
		_pvp_textures[path] = texture
	return _pvp_textures[path]


static func is_group_leader(unit: int) -> bool:
	return PartyFrame.in_party() and PartyFrame.leader == unit


func show_unit(unit: int) -> void:
	guid = unit
	_display = 0
	refresh()


func portrait_texture() -> Texture2D:
	return _portrait.get_texture()


func refresh() -> void:
	var session: WowSession = WowClient.session
	visible = guid != 0 and session.has_object(guid)
	if not visible:
		return
	_name_label.text = session.get_object_name(guid)
	if _level_label:
		_level_label.text = str(session.get_field(guid, "UNIT_FIELD_LEVEL"))
	var health: int = session.get_field(guid, "UNIT_FIELD_HEALTH")
	var max_health: int = maxi(session.get_field(guid, "UNIT_FIELD_MAXHEALTH"), 1)
	_health_bar.max_value = max_health
	_health_bar.value = health
	_health_bar.tint_progress = HEALTH_COLOR
	if _health_text:
		_health_text.text = "%d / %d" % [health, max_health]
	var bytes_0: int = session.get_field(guid, "UNIT_FIELD_BYTES_0")
	var power_type: PowerType = ((bytes_0 >> 24) & 0xFF) as PowerType
	var first_power: int = session.field_index("UNIT_FIELD_POWER1")
	var first_max: int = session.field_index("UNIT_FIELD_MAXPOWER1")
	var power_scale: int = RAGE_SCALE if power_type == PowerType.RAGE else 1
	var power: int = floori(session.get_field(guid, first_power + power_type) / float(power_scale))
	var max_power: int = floori(session.get_field(guid, first_max + power_type) / float(power_scale))
	_power_bar.max_value = maxi(max_power, 1)
	_power_bar.value = power
	_power_bar.tint_progress = POWER_COLORS.get(power_type, POWER_COLORS[PowerType.MANA])
	if _power_text:
		_power_text.text = "%d / %d" % [power, max_power]
	var display: int = session.get_field(guid, "UNIT_FIELD_DISPLAYID")
	if display != _display:
		_display = display
		_portrait.show_unit(guid)
	_update_unit()


# Frame-specific state such as status icons, called at the end of every refresh.
func _update_unit() -> void:
	pass


# The stock STATUS_BAR_TEXT option keeps the numbers up; otherwise they answer the cursor.
func _show_bar_text(shown: bool) -> void:
	var always: bool = WowAssets.interface.is_on(&"status_bar_text")
	for text: Label in [_health_text, _power_text]:
		if text:
			text.visible = shown or always


func _on_mouse_entered() -> void:
	if guid != 0 and GameTooltip.current:
		GameTooltip.current.set_unit(self, guid)


func _on_mouse_exited() -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(self)


func _on_object_updated(unit: int) -> void:
	if unit == guid:
		refresh()


func _on_name_received(unit: int, unit_name: String) -> void:
	if unit == guid:
		_name_label.text = unit_name


func _on_objects_destroyed(guids: PackedInt64Array) -> void:
	if guids.has(guid):
		show_unit(0)
