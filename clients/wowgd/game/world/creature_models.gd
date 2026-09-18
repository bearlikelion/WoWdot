class_name CreatureModels
extends RefCounted

enum TextureSlot { MONSTER_SKIN_1 = 11, MONSTER_SKIN_2 = 12, MONSTER_SKIN_3 = 13 }

const SKIN_COLUMNS: Dictionary[String, TextureSlot] = {
	"Skin1": TextureSlot.MONSTER_SKIN_1,
	"Skin2": TextureSlot.MONSTER_SKIN_2,
	"Skin3": TextureSlot.MONSTER_SKIN_3,
}

var _loader: WowLoader
var _display_info: WowDBC
var _model_data: WowDBC


func _init(loader: WowLoader) -> void:
	_loader = loader
	_display_info = WowDBC.open(loader.archive, "CreatureDisplayInfo")
	_model_data = WowDBC.open(loader.archive, "CreatureModelData")


func instantiate(display_id: int) -> Node3D:
	var row: int = _display_info.find(display_id)
	if row < 0:
		return null
	var model_row: int = _model_data.find(_display_info.get_uint(row, "ModelID"))
	if model_row < 0:
		return null
	var model_path: String = _model_data.get_string(model_row, "ModelPath").replace("\\", "/")
	# Display skins are bare names that live next to the model.
	var skins: Dictionary = {}
	for column: String in SKIN_COLUMNS:
		var skin: String = _display_info.get_string(row, column)
		if not skin.is_empty():
			skins[SKIN_COLUMNS[column]] = model_path.get_base_dir().path_join(skin + ".blp")
	var model: Node3D = _loader.load_m2(model_path, skins)
	if model:
		var scale: float = _display_info.get_float(row, "Scale")
		model.scale = Vector3.ONE * (scale if scale > 0.0 else 1.0)
	return model
