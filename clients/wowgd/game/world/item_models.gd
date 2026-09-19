class_name ItemModels
extends RefCounted

enum Slot { HEAD, SHOULDERS, MAIN_HAND, OFF_HAND }
# M2 attachment point ids.
enum Attachment {
	SHIELD = 0, HAND_RIGHT = 1, HAND_LEFT = 2, SHOULDER_RIGHT = 5, SHOULDER_LEFT = 6, HELM = 11,
}

const COMPONENTS: String = "Item\\ObjectComponents\\"
# Item models take their ItemDisplayInfo texture as texture type 2.
const ITEM_SKIN: int = 2
const GENDERS: Array[String] = ["M", "F"]

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
	var points: Dictionary[int, Dictionary] = {}
	for point: Dictionary in _loader.get_m2_info(model_path).get("attachments", []):
		points[int(point["id"])] = point
	match slot:
		Slot.HEAD:
			var prefix: String = _races.get_string(_races.find(race), "ClientPrefix")
			var suffix: String = "_%s%s" % [prefix, GENDERS[clampi(gender, 0, 1)]]
			_mount(model, points.get(Attachment.HELM, {}), row, "Left", "Head\\", suffix)
		Slot.SHOULDERS:
			_mount(model, points.get(Attachment.SHOULDER_LEFT, {}), row, "Left", "Shoulder\\")
			_mount(model, points.get(Attachment.SHOULDER_RIGHT, {}), row, "Right", "Shoulder\\")
		Slot.MAIN_HAND:
			_mount(model, points.get(Attachment.HAND_RIGHT, {}), row, "Left", "Weapon\\")
		Slot.OFF_HAND:
			if _exists(row, "Left", "Shield\\"):
				_mount(model, points.get(Attachment.SHIELD, {}), row, "Left", "Shield\\")
			else:
				_mount(model, points.get(Attachment.HAND_LEFT, {}), row, "Left", "Weapon\\")


func _mount(
	model: Node3D, point: Dictionary, row: int, side: String, folder: String, suffix: String = "",
) -> void:
	var skeleton: Skeleton3D = model.find_child("Skeleton", true, false)
	if point.is_empty() or skeleton == null or not _exists(row, side, folder, suffix):
		return
	var skins: Dictionary = {}
	var texture: String = _displays.get_string(row, side + "ModelTexture")
	if not texture.is_empty():
		skins[ITEM_SKIN] = COMPONENTS + folder + texture + ".blp"
	var item: Node3D = _loader.load_m2(_path(row, side, folder, suffix), skins)
	if item == null:
		return
	var bone: int = point["bone"]
	var holder: BoneAttachment3D = BoneAttachment3D.new()
	holder.bone_name = skeleton.get_bone_name(bone)
	skeleton.add_child(holder)
	holder.add_child(item)
	# Attachment positions are in model space; the holder already sits on the bone's pivot.
	item.position = (point["position"] as Vector3) - skeleton.get_bone_global_rest(bone).origin


func _exists(row: int, side: String, folder: String, suffix: String = "") -> bool:
	var path: String = _path(row, side, folder, suffix)
	return not path.is_empty() and _loader.archive.has(path)


# ItemDisplayInfo names the .mdx the model shipped as; the archive holds it as .m2.
func _path(row: int, side: String, folder: String, suffix: String) -> String:
	var file: String = _displays.get_string(row, side + "Model")
	if file.is_empty():
		return ""
	return COMPONENTS + folder + file.get_basename() + suffix + ".m2"
