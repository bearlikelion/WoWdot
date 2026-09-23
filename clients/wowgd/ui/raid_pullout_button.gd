class_name RaidPulloutButton
extends Control

signal unit_selected(guid: int)
signal menu_requested

const AURAS: int = 4
# RAID_CLASS_COLORS from Fonts.xml.
const CLASS_COLORS: Dictionary[String, Color] = {
	"HUNTER": Color(0.67, 0.83, 0.45), "WARLOCK": Color(0.58, 0.51, 0.79),
	"PRIEST": Color(1.0, 1.0, 1.0), "PALADIN": Color(0.96, 0.55, 0.73),
	"MAGE": Color(0.41, 0.8, 0.94), "ROGUE": Color(1.0, 0.96, 0.41),
	"DRUID": Color(1.0, 0.49, 0.04), "SHAMAN": Color(0.96, 0.55, 0.73),
	"WARRIOR": Color(0.78, 0.61, 0.43),
}
const DEAD_COLOR: Color = Color(1.0, 0.1, 0.1)
const OFFLINE_COLOR: Color = Color(0.5, 0.5, 0.5)

var _guid: int = 0

@onready var _name: Label = $Name
@onready var _health: TextureProgressBar = $HealthBar
@onready var _power: TextureProgressBar = $ManaBar


func _ready() -> void:
	# The name is tinted like SetVertexColor, so it starts from the white font.
	_name.theme_type_variation = &"GameFontHighlightSmall"
	($ClearButton as Control).gui_input.connect(_on_clear_input)
	for i: int in AURAS:
		(get_node("Debuff%d" % (i + 1)) as CanvasItem).hide()


# RaidPullout_Update for one member: name tinted by class, dead or offline, then the bars and auras.
func show_member(member: Dictionary, stats: Dictionary, show_buffs: bool) -> void:
	_guid = member["guid"]
	_name.text = member["name"]
	var session: WowSession = WowClient.session
	var in_sight: bool = session.has_object(_guid)
	var health: int = session.get_field(_guid, "UNIT_FIELD_HEALTH") if in_sight \
			else stats.get("health", 0)
	var max_health: int = session.get_field(_guid, "UNIT_FIELD_MAXHEALTH") if in_sight \
			else stats.get("max_health", 1)
	var power_type: UnitFrame.PowerType = stats.get("power_type", 0) as UnitFrame.PowerType
	var power: int = stats.get("power", 0)
	var max_power: int = stats.get("max_power", 1)
	var class_file: String = ""
	if in_sight:
		var bytes_0: int = session.get_field(_guid, "UNIT_FIELD_BYTES_0")
		power_type = ((bytes_0 >> 24) & 0xFF) as UnitFrame.PowerType
		power = session.get_field(_guid, session.field_index("UNIT_FIELD_POWER1") + power_type)
		max_power = session.get_field(_guid, session.field_index("UNIT_FIELD_MAXPOWER1") + power_type)
		class_file = CharacterOptions.class_file((bytes_0 >> 8) & 0xFF)
	if not member["online"]:
		_name.self_modulate = OFFLINE_COLOR
	elif health == 0:
		_name.self_modulate = DEAD_COLOR
	else:
		_name.self_modulate = CLASS_COLORS.get(class_file, Color.WHITE)
	_health.max_value = maxi(max_health, 1)
	_health.value = _health.max_value if not member["online"] else health
	_health.tint_progress = UnitFrame.HEALTH_COLOR if member["online"] else OFFLINE_COLOR
	_power.max_value = maxi(max_power, 1)
	_power.value = power
	_power.tint_progress = UnitFrame.POWER_COLORS.get(
		power_type, UnitFrame.POWER_COLORS[UnitFrame.PowerType.MANA]
	)
	_show_auras(show_buffs, in_sight)


func _show_auras(show_buffs: bool, in_sight: bool) -> void:
	var shown: Array[Dictionary] = []
	if in_sight:
		for aura: Dictionary in UnitAuras.read(WowClient.session, _guid):
			if aura["harmful"] != show_buffs:
				shown.append(aura)
	for i: int in AURAS:
		var slot: Control = get_node("Debuff%d" % (i + 1))
		slot.visible = i < shown.size()
		if slot.visible:
			var spell: int = shown[i]["spell"]
			(slot.get_node("Icon") as TextureRect).texture = WowAssets.spells.icon(spell)
			(slot.get_node("Border") as TextureRect).self_modulate = \
					UnitAuras.border_color(spell) if not show_buffs else Color.TRANSPARENT


# RaidPulloutButton_OnClick: a left click targets the member, a right click opens the menu.
func _on_clear_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or click.pressed:
		return
	if click.button_index == MOUSE_BUTTON_RIGHT:
		menu_requested.emit()
	elif click.button_index == MOUSE_BUTTON_LEFT:
		unit_selected.emit(_guid)
