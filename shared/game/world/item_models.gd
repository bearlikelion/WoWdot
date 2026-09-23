class_name ItemModels
extends RefCounted

enum Slot { HEAD, SHOULDERS, MAIN_HAND, OFF_HAND, RANGED }
# M2 attachment point ids.
enum Attachment {
	NONE = -1, SHIELD = 0, HAND_RIGHT = 1, HAND_LEFT = 2, SHOULDER_RIGHT = 5, SHOULDER_LEFT = 6,
	HELM = 11, SHEATH_MAIN_HAND = 26, SHEATH_OFF_HAND = 27, SHEATH_SHIELD = 28,
	LARGE_WEAPON_LEFT = 30, LARGE_WEAPON_RIGHT = 31, HIP_WEAPON_LEFT = 32, HIP_WEAPON_RIGHT = 33,
}
# item_template sheath values as the stock DB fills them.
enum Sheath { NONE, TWO_HANDED, STAFF, ONE_HANDED, SHIELD }
# UNIT_FIELD_BYTES_2 byte 0.
enum SheathState { UNARMED, MELEE, RANGED }
enum WeaponSubclass { BOW = 2, GUN = 3, THROWN = 16, CROSSBOW = 18, WAND = 19 }

const COMPONENTS: String = "Item\\ObjectComponents\\"
# Item models take their ItemDisplayInfo texture as texture type 2.
const ITEM_SKIN: int = 2
const AMMO_FOLDER: String = "Ammo\\"
const WEAPON_FOLDER: String = "Weapon\\"
const GENDERS: Array[String] = ["M", "F"]
const WEAPON_SLOTS: Array[Slot] = [Slot.MAIN_HAND, Slot.OFF_HAND, Slot.RANGED]
# Where a sheathed weapon hangs, x for the main hand and y for the off hand.
const SHEATH_POINTS: Dictionary[Sheath, Vector2i] = {
	Sheath.TWO_HANDED: Vector2i(Attachment.SHEATH_MAIN_HAND, Attachment.SHEATH_OFF_HAND),
	Sheath.STAFF: Vector2i(Attachment.LARGE_WEAPON_LEFT, Attachment.LARGE_WEAPON_RIGHT),
	Sheath.ONE_HANDED: Vector2i(Attachment.HIP_WEAPON_LEFT, Attachment.HIP_WEAPON_RIGHT),
	Sheath.SHIELD: Vector2i(Attachment.SHEATH_SHIELD, Attachment.SHEATH_SHIELD),
}
# Ranged items all have sheath 0; bows, guns and crossbows ride centred on the back.
const BACK_RANGED: Array[WeaponSubclass] = [
	WeaponSubclass.BOW, WeaponSubclass.GUN, WeaponSubclass.CROSSBOW,
]

var _loader: WowLoader
var _displays: WowDBC
var _races: WowDBC


func _init(loader: WowLoader) -> void:
	_loader = loader
	_displays = WowDBC.open(loader.archive, "ItemDisplayInfo")
	_races = WowDBC.open(loader.archive, "ChrRaces")


# Hangs an item's models on the model's attachment points; race and gender pick a helmet's cut.
func attach(
	model: Node3D, model_path: String, slot: Slot, display_id: int, race: int = 0, gender: int = 0,
) -> void:
	var row: int = _displays.find(display_id) if display_id > 0 else -1
	if row < 0:
		return
	var points: Dictionary[int, Dictionary] = _points(model_path)
	match slot:
		Slot.HEAD:
			var prefix: String = _races.get_string(_races.find(race), "ClientPrefix")
			var suffix: String = "_%s%s" % [prefix, GENDERS[clampi(gender, 0, 1)]]
			_mount(model, points.get(Attachment.HELM, {}), row, "Left", "Head\\", suffix)
		Slot.SHOULDERS:
			_mount(model, points.get(Attachment.SHOULDER_LEFT, {}), row, "Left", "Shoulder\\")
			_mount(model, points.get(Attachment.SHOULDER_RIGHT, {}), row, "Right", "Shoulder\\")


# The arrow, bullet or thrown weapon a ranged shot flies as; ammo keeps its model on the right.
func load_ammo(display_id: int) -> Node3D:
	var row: int = _displays.find(display_id) if display_id > 0 else -1
	if row < 0:
		return null
	var side: String = "Right"
	var folder: String = AMMO_FOLDER
	if _exists(row, "Left", WEAPON_FOLDER):
		side = "Left"
		folder = WEAPON_FOLDER
	elif not _exists(row, side, folder):
		return null
	var skins: Dictionary = {}
	var texture: String = _displays.get_string(row, side + "ModelTexture")
	if not texture.is_empty():
		skins[ITEM_SKIN] = COMPONENTS + folder + texture + ".blp"
	return _loader.load_m2(_path(row, side, folder, ""), skins)


# Hangs the unit's main hand, off hand and ranged weapons where its sheath state puts them.
func arm(model: Node3D, model_path: String, weapons: Array, state: SheathState) -> void:
	var skeleton: Skeleton3D = model.find_child("Skeleton", true, false)
	if skeleton == null:
		return
	var points: Dictionary[int, Dictionary] = _points(model_path)
	for i: int in mini(weapons.size(), WEAPON_SLOTS.size()):
		var slot: Slot = WEAPON_SLOTS[i]
		var old: Node = skeleton.get_node_or_null(Slot.find_key(slot))
		if old:
			skeleton.remove_child(old)
			old.queue_free()
		var weapon: Weapon = weapons[i]
		var row: int = _displays.find(weapon.display) if weapon.display > 0 else -1
		if row < 0:
			continue
		var folder: String = "Shield\\" if _exists(row, "Left", "Shield\\") else WEAPON_FOLDER
		var main_sheath: Sheath = (weapons[0] as Weapon).sheath
		var point: Attachment = _weapon_point(slot, weapon, state, folder, main_sheath)
		var holder: Node3D = _mount(model, points.get(point, {}), row, "Left", folder)
		if holder:
			holder.name = Slot.find_key(slot)


# The main hand, off hand and ranged weapons a creature holds, from its virtual item fields.
static func unit_weapons(session: WowSession, guid: int) -> Array[Weapon]:
	var displays: int = session.field_index("UNIT_VIRTUAL_ITEM_SLOT_DISPLAY")
	var infos: int = session.field_index("UNIT_VIRTUAL_ITEM_INFO")
	var weapons: Array[Weapon] = []
	if displays < 0:
		# 3.3.5 sends item entries instead, so the look comes from the item query.
		var entries: int = session.field_index("UNIT_VIRTUAL_ITEM_SLOT_ID")
		for i: int in WEAPON_SLOTS.size():
			var entry: int = session.get_field(guid, entries + i)
			var info: Dictionary = session.get_item_info(entry) if entry != 0 else {}
			weapons.append(Weapon.new(
				info.get("display_id", 0), info.get("sheath", 0), info.get("subclass", 0)
			))
		return weapons
	for i: int in WEAPON_SLOTS.size():
		var info: int = session.get_field(guid, infos + i * 2)
		weapons.append(Weapon.new(
			session.get_field(guid, displays + i),
			session.get_field(guid, infos + i * 2 + 1) & 0xFF,
			(info >> 8) & 0xFF,
		))
	return weapons


static func unit_weapons_pending(session: WowSession, guid: int) -> bool:
	var entries: int = session.field_index("UNIT_VIRTUAL_ITEM_SLOT_ID")
	if entries < 0:
		return false
	for i: int in WEAPON_SLOTS.size():
		var entry: int = session.get_field(guid, entries + i)
		if entry != 0 and session.get_item_info(entry).is_empty():
			return true
	return false


static func sheath_state(session: WowSession, guid: int) -> SheathState:
	return (session.get_field(guid, "UNIT_FIELD_BYTES_2") & 0xFF) as SheathState


# A sheathed ranged weapon crosses the main hand's; a staff takes its usual spot.
func _weapon_point(
	slot: Slot, weapon: Weapon, state: SheathState, folder: String, main_sheath: Sheath,
) -> Attachment:
	if slot == Slot.RANGED:
		if state == SheathState.RANGED:
			return Attachment.HAND_LEFT if weapon.subclass == WeaponSubclass.BOW \
			else Attachment.HAND_RIGHT
		if weapon.subclass not in BACK_RANGED:
			return Attachment.NONE
		return Attachment.LARGE_WEAPON_RIGHT if main_sheath == Sheath.STAFF \
		else Attachment.LARGE_WEAPON_LEFT
	if state != SheathState.MELEE and SHEATH_POINTS.has(weapon.sheath):
		var sheathed: Vector2i = SHEATH_POINTS[weapon.sheath]
		return (sheathed.x if slot == Slot.MAIN_HAND else sheathed.y) as Attachment
	if slot == Slot.MAIN_HAND:
		return Attachment.HAND_RIGHT
	return Attachment.SHIELD if folder == "Shield\\" else Attachment.HAND_LEFT


func _points(model_path: String) -> Dictionary[int, Dictionary]:
	var points: Dictionary[int, Dictionary] = {}
	for point: Dictionary in _loader.get_m2_info(model_path).get("attachments", []):
		points[int(point["id"])] = point
	return points


func _mount(
	model: Node3D, point: Dictionary, row: int, side: String, folder: String, suffix: String = "",
) -> Node3D:
	var skeleton: Skeleton3D = model.find_child("Skeleton", true, false)
	if point.is_empty() or skeleton == null or not _exists(row, side, folder, suffix):
		return null
	var skins: Dictionary = {}
	var texture: String = _displays.get_string(row, side + "ModelTexture")
	if texture.is_empty():
		texture = _displays.get_string(row, "LeftModelTexture")
	if not texture.is_empty():
		skins[ITEM_SKIN] = COMPONENTS + folder + texture + ".blp"
	var item: Node3D = _loader.load_m2(_path(row, side, folder, suffix), skins)
	if item == null:
		return null
	CreatureModels.mark_unit(item)
	var bone: int = point["bone"]
	var holder: BoneAttachment3D = BoneAttachment3D.new()
	holder.bone_name = skeleton.get_bone_name(bone)
	skeleton.add_child(holder)
	holder.add_child(item)
	# Attachment positions are in model space; the holder already sits on the bone's pivot.
	item.position = (point["position"] as Vector3) - skeleton.get_bone_global_rest(bone).origin
	return holder


func _exists(row: int, side: String, folder: String, suffix: String = "") -> bool:
	var path: String = _path(row, side, folder, suffix)
	return not path.is_empty() and _loader.archive.has(path)


# ItemDisplayInfo names the .mdx the model shipped as; the archive holds it as .m2.
func _path(row: int, side: String, folder: String, suffix: String) -> String:
	var file: String = _displays.get_string(row, side + "Model")
	# Most shoulders list only the left pad; the right one is its RShoulder twin.
	var left: String = _displays.get_string(row, "LeftModel")
	if file.is_empty() and side == "Right" and left.to_lower().begins_with("lshoulder"):
		file = "R" + left.substr(1)
	if file.is_empty():
		return ""
	return COMPONENTS + folder + file.get_basename() + suffix + ".m2"


class Weapon:
	var display: int = 0
	var sheath: Sheath = Sheath.NONE
	var subclass: int = 0


	func _init(display_id: int = 0, sheath_type: int = Sheath.NONE, item_subclass: int = 0) -> void:
		display = display_id
		sheath = sheath_type as Sheath
		subclass = item_subclass
