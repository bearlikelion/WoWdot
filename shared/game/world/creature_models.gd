class_name CreatureModels
extends RefCounted

enum TextureSlot { MONSTER_SKIN_1 = 11, MONSTER_SKIN_2 = 12, MONSTER_SKIN_3 = 13 }

# Unit models draw on their own layer, so the selection circle paints only the ground under them.
const UNIT_LAYER: int = 2
const SKIN_COLUMNS: Dictionary[String, TextureSlot] = {
	"Skin1": TextureSlot.MONSTER_SKIN_1,
	"Skin2": TextureSlot.MONSTER_SKIN_2,
	"Skin3": TextureSlot.MONSTER_SKIN_3,
}

var _loader: WowLoader
var _characters: CharacterModels
var _display_info: WowDBC
var _display_extra: WowDBC
var _model_data: WowDBC


func _init(loader: WowLoader, characters: CharacterModels) -> void:
	_loader = loader
	_characters = characters
	_display_info = WowDBC.open(loader.archive, "CreatureDisplayInfo")
	_display_extra = WowDBC.open(loader.archive, "CreatureDisplayInfoExtra")
	_model_data = WowDBC.open(loader.archive, "CreatureModelData")


func model_path(display_id: int) -> String:
	var row: int = _display_info.find(display_id)
	var model_row: int = _model_data.find(_display_info.get_uint(row, "ModelID")) if row >= 0 else -1
	return _model_data.get_string(model_row, "ModelPath").replace("\\", "/") if model_row >= 0 else ""


# Humanoid NPCs and players look like characters, so any look given here is applied as one.
func instantiate(display_id: int, look: Dictionary = {}) -> Node3D:
	var row: int = _display_info.find(display_id)
	if row < 0:
		return null
	var model_row: int = _model_data.find(_display_info.get_uint(row, "ModelID"))
	if model_row < 0:
		return null
	var path: String = _model_data.get_string(model_row, "ModelPath").replace("\\", "/")
	var extra: int = _display_extra.find(_display_info.get_uint(row, "ExtraDisplayId"))
	if look.is_empty() and extra >= 0:
		look = {
			"race": _display_extra.get_uint(extra, "RaceID"),
			"gender": _display_extra.get_uint(extra, "SexID"),
			"skin": _display_extra.get_uint(extra, "SkinID"),
			"face": _display_extra.get_uint(extra, "FaceID"),
			"hair_style": _display_extra.get_uint(extra, "HairStyleID"),
			"hair_color": _display_extra.get_uint(extra, "HairColorID"),
			"facial_hair": _display_extra.get_uint(extra, "FacialHairID"),
			"baked": _display_extra.get_string(extra, "BakeName"),
			"equipment": _equipment(extra),
		}
	if not look.is_empty():
		return _scaled(_characters.instantiate(path, look), row)
	# Display skins are bare names that live next to the model.
	var skins: Dictionary = {}
	for column: String in SKIN_COLUMNS:
		var skin: String = _display_info.get_string(row, column)
		if not skin.is_empty():
			skins[SKIN_COLUMNS[column]] = path.get_base_dir().path_join(skin + ".blp")
	return _scaled(_loader.load_m2(path, skins), row)


static func mark_unit(model: Node3D) -> void:
	for mesh: Node in model.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).layers = UNIT_LAYER


func _equipment(extra: int) -> PackedInt32Array:
	var displays: PackedInt32Array = []
	for slot: int in CharacterModels.EquipSlot.size():
		displays.append(_display_extra.get_uint(extra, "EquipDisplay%d" % slot))
	return displays


func _scaled(model: Node3D, row: int) -> Node3D:
	if model:
		var scale: float = _display_info.get_float(row, "Scale")
		model.scale = Vector3.ONE * (scale if scale > 0.0 else 1.0)
		mark_unit(model)
	return model
