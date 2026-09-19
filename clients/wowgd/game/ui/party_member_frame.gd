class_name PartyMemberFrame
extends UnitFrame

const OFFLINE_TINT: Color = Color(0.5, 0.5, 0.5)

var member_name: String = ""
var online: bool = true

# The converter keeps a name unique only once, and the pet frame repeats these.
@onready var _member_label: Label = $Frame/Frame/Name
@onready var _leader_icon: TextureRect = %LeaderIcon
@onready var _disconnect_icon: TextureRect = %Disconnect


func _ready() -> void:
	_name_label = _member_label
	_health_bar = $HealthBar
	_power_bar = %ManaBar
	_portrait_rect = $Portrait
	# ponytail: no party pets, debuffs or status icons yet; add them with the aura port.
	for unused: String in ["%DropDown", "%PetFrame", "%Status", "%PVPIcon", "%MasterIcon"]:
		(get_node(unused) as Control).hide()
	for i: int in 4:
		(get_node("Debuff%d" % (i + 1)) as Control).hide()
	super()


func show_member(member: Dictionary, is_leader: bool) -> void:
	member_name = member.get("name", "")
	online = member.get("online", false)
	_leader_icon.visible = is_leader
	show_unit(member.get("guid", 0))


# A member out of sight has no object to read, so only the name shows.
func refresh() -> void:
	super()
	if member_name.is_empty() or visible:
		_update_status()
		return
	show()
	_name_label.text = member_name
	_health_bar.value = 0.0
	_power_bar.value = 0.0
	_update_status()


func _update_status() -> void:
	_disconnect_icon.visible = not online
	modulate = Color.WHITE if online else OFFLINE_TINT
