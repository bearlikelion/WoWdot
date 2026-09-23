@tool
class_name PartyMemberFrame
extends UnitFrame

const OFFLINE_TINT: Color = Color(0.5, 0.5, 0.5)

const DEBUFFS: int = 4

var member_name: String = ""
var online: bool = true
var remote_stats: Dictionary = {}
var _debuffs: Array[Control] = []
var _pet_debuffs: Array[Control] = []
var _pet_portrait: UnitPortrait
var _pet_display: int = 0

# The converter keeps a name unique only once, and the pet frame repeats these.
@onready var _member_label: Label = $Frame/Frame/Name
@onready var _leader_icon: TextureRect = %LeaderIcon
@onready var _disconnect_icon: TextureRect = %Disconnect
@onready var _pvp_icon: TextureRect = %PVPIcon
@onready var _master_icon: TextureRect = %MasterIcon
@onready var _pet_frame: WowButton = %PetFrame
@onready var _pet_name: Label = $PetFrame/Frame/Frame/Name
@onready var _pet_health: TextureProgressBar = $PetFrame/HealthBar


func _ready() -> void:
	if Engine.is_editor_hint():
		super()
		return
	_name_label = _member_label
	_health_bar = $HealthBar
	_power_bar = %ManaBar
	_portrait_rect = $Portrait
	for unused: String in ["%DropDown", "%Status"]:
		(get_node(unused) as Control).hide()
	for i: int in DEBUFFS:
		_debuffs.append(get_node("Debuff%d" % (i + 1)))
		_debuffs[i].hide()
		_pet_debuffs.append(_pet_frame.get_node("Debuff%d" % (i + 1)))
		_pet_debuffs[i].hide()
	_pet_portrait = PORTRAIT.instantiate()
	add_child(_pet_portrait)
	var pet_portrait_rect: TextureRect = $PetFrame/Portrait
	var mask: ShaderMaterial = ShaderMaterial.new()
	mask.shader = PORTRAIT_MASK
	pet_portrait_rect.material = mask
	pet_portrait_rect.texture = _pet_portrait.get_texture()
	_pet_frame.pressed.connect(func() -> void: unit_selected.emit(_pet_guid()))
	_pet_health.tint_progress = HEALTH_COLOR
	super()
	WowClient.session.object_updated.connect(func(updated: int) -> void:
		if updated != 0 and updated == _pet_guid() and visible:
			_update_pet()
	)


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
		_update_pet()
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
	_update_pet()


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
	_master_icon.visible = UnitFrame.is_master_looter(guid)
	_pvp_icon.texture = UnitFrame.pvp_texture(guid)
	_pvp_icon.visible = _pvp_icon.texture != null
	modulate = Color.WHITE if online else OFFLINE_TINT


# The member's pet object when in sight, else the pet their party stats report.
func _pet_guid() -> int:
	var session: WowSession = WowClient.session
	if session.has_object(guid):
		return session.get_field_guid(guid, "UNIT_FIELD_SUMMON")
	return remote_stats.get("pet_guid", 0)


# PartyMemberFrame_UpdatePet: the pet's name, health, portrait and first debuffs under its owner.
func _update_pet() -> void:
	var pet: int = _pet_guid()
	_pet_frame.visible = online and pet != 0
	if not _pet_frame.visible:
		return
	var session: WowSession = WowClient.session
	var harmful: Array[Dictionary] = []
	if session.has_object(pet):
		_pet_name.text = session.get_object_name(pet)
		_pet_health.max_value = maxi(session.get_field(pet, "UNIT_FIELD_MAXHEALTH"), 1)
		_pet_health.value = session.get_field(pet, "UNIT_FIELD_HEALTH")
		var display: int = session.get_field(pet, "UNIT_FIELD_DISPLAYID")
		if display != _pet_display:
			_pet_display = display
			_pet_portrait.show_unit(pet)
		for aura: Dictionary in UnitAuras.read(session, pet):
			if aura["harmful"]:
				harmful.append(aura)
	else:
		_pet_name.text = remote_stats.get("pet_name", "")
		_pet_health.max_value = maxi(remote_stats.get("pet_max_health", 1), 1)
		_pet_health.value = remote_stats.get("pet_health", 0)
	for i: int in DEBUFFS:
		_pet_debuffs[i].visible = i < harmful.size()
		if _pet_debuffs[i].visible:
			var spell: int = harmful[i]["spell"]
			(_pet_debuffs[i].get_node("Icon") as TextureRect).texture = WowAssets.spells.icon(spell)
			(_pet_debuffs[i].get_node("Border") as TextureRect).self_modulate = \
					UnitAuras.border_color(spell)
