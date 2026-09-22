@tool
class_name PartyMemberFrame
extends UnitFrame

const OFFLINE_TINT: Color = Color(0.5, 0.5, 0.5)

const DEBUFFS: int = 4

var member_name: String = ""
var online: bool = true
var remote_stats: Dictionary = {}
var _debuffs: Array[Control] = []

# The converter keeps a name unique only once, and the pet frame repeats these.
@onready var _member_label: Label = $Frame/Frame/Name
@onready var _leader_icon: TextureRect = %LeaderIcon
@onready var _disconnect_icon: TextureRect = %Disconnect


func _ready() -> void:
	if Engine.is_editor_hint():
		super()
		return
	_name_label = _member_label
	_health_bar = $HealthBar
	_power_bar = %ManaBar
	_portrait_rect = $Portrait
	# ponytail: no party pets or status icons yet.
	for unused: String in ["%DropDown", "%PetFrame", "%Status", "%PVPIcon", "%MasterIcon"]:
		(get_node(unused) as Control).hide()
	for i: int in DEBUFFS:
		_debuffs.append(get_node("Debuff%d" % (i + 1)))
		_debuffs[i].hide()
	super()


func show_member(member: Dictionary, is_leader: bool) -> void:
	member_name = member.get("name", "")
	online = member.get("online", false)
	_leader_icon.visible = is_leader
	show_unit(member.get("guid", 0))


# A member out of sight has no object to read, so the bars come from the server's reports.
func refresh() -> void:
	super()
	if member_name.is_empty() or visible:
		_update_status()
		_update_debuffs()
		return
	show()
	_name_label.text = member_name
	_health_bar.max_value = maxi(remote_stats.get("max_health", 1), 1)
	_health_bar.value = remote_stats.get("health", 0)
	_power_bar.max_value = maxi(remote_stats.get("max_power", 1), 1)
	_power_bar.value = remote_stats.get("power", 0)
	var power_type: PowerType = remote_stats.get("power_type", PowerType.MANA) as PowerType
	_power_bar.tint_progress = POWER_COLORS.get(power_type, POWER_COLORS[PowerType.MANA])
	_update_status()


# PartyMemberFrame_RefreshDebuffs: the first four harmful auras, bordered by dispel type.
func _update_debuffs() -> void:
	var harmful: Array[Dictionary] = []
	for aura: Dictionary in UnitAuras.read(WowClient.session, guid):
		if aura["harmful"]:
			harmful.append(aura)
	for i: int in DEBUFFS:
		_debuffs[i].visible = i < harmful.size()
		if _debuffs[i].visible:
			var spell: int = harmful[i]["spell"]
			(_debuffs[i].get_node("Icon") as TextureRect).texture = WowAssets.spells.icon(spell)
			(_debuffs[i].get_node("Border") as TextureRect).self_modulate = UnitAuras.border_color(spell)


func _update_status() -> void:
	_disconnect_icon.visible = not online
	modulate = Color.WHITE if online else OFFLINE_TINT
