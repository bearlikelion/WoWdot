class_name CharacterOptions
extends RefCounted

enum Faction { ALLIANCE, HORDE }
enum Gender { MALE, FEMALE }

# GetAvailableRaces order: the Alliance column of buttons, then the Horde one.
const RACE_ORDER: Array[int] = [1, 3, 4, 7, 2, 5, 6, 8]
# 3.3.5 adds Draenei to the Alliance column and Blood Elves to the Horde one.
const RACE_ORDER_WOTLK: Array[int] = [1, 3, 4, 7, 11, 2, 5, 6, 8, 10]
# The race icon sheet holds four columns in 1.12 and eight from Burning Crusade on.
const RACE_ICON_COLUMNS: Dictionary[String, float] = {"classic": 0.25, "wotlk": 0.125}
const LANGUAGE_COMMON: int = 7
const SCENE_PATH: String = "Interface\\Glues\\Models\\UI_%s\\UI_%s.m2"
# SetBackgroundModel: gnomes and trolls have no scene of their own.
const SCENE_STAND_INS: Dictionary[String, String] = {"Gnome": "Dwarf", "Troll": "Orc"}
# CharModelFogInfo from GlueParent.lua, colour and far distance by scene.
const SCENE_FOG: Dictionary[String, Array] = {
	"Human": [Color(0.8, 0.65, 0.73), 222.0],
	"Orc": [Color(0.5, 0.5, 0.5), 270.0],
	"Dwarf": [Color(0.85, 0.88, 1.0), 500.0],
	"NightElf": [Color(0.25, 0.22, 0.55), 611.0],
	"Tauren": [Color(1.0, 0.61, 0.42), 153.0],
	"Scourge": [Color(0.0, 0.22, 0.22), 26.0],
}
# RaceLights from GlueParent.lua: direction, then ambient and direct intensity and colour.
const SCENE_LIGHTS: Dictionary[String, Array] = {
	"Human": [
		[
			Vector3(0.0, 0.0, -1.0),
			1.0, Color(0.27, 0.27, 0.27), 1.0, Color(0.0, 0.0, 0.0),
		],
		[
			Vector3(-0.45756075, -0.58900136, -0.66611975),
			1.0, Color(0.0, 0.0, 0.0), 1.0, Color(0.19882353, 0.34921569, 0.43588236),
		],
		[
			Vector3(-0.64623469, 0.57582057, -0.50081086),
			1.0, Color(0.0, 0.0, 0.0), 2.0, Color(0.52196085, 0.44, 0.29764709),
		],
	],
	"Orc": [
		[
			Vector3(0.0, 0.0, -1.0),
			1.0, Color(0.15, 0.15, 0.15), 1.0, Color(0.0, 0.0, 0.0),
		],
		[
			Vector3(-0.74919, 0.35208, -0.56103),
			1.0, Color(0.0, 0.0, 0.0), 1.0, Color(0.44706, 0.5451, 0.73725),
		],
		[
			Vector3(0.53162, -0.8434, 0.0778),
			1.0, Color(0.0, 0.0, 0.0), 2.0, Color(0.55, 0.338625, 0.148825),
		],
	],
	"Dwarf": [
		[
			Vector3(0.0, 0.0, -1.0),
			1.0, Color(0.3, 0.3, 0.3), 0.0, Color(0.0, 0.0, 0.0),
		],
		[
			Vector3(-0.88314, 0.42916, -0.18945),
			1.0, Color(0.0, 0.0, 0.0), 2.0, Color(0.44706, 0.67451, 0.760785),
		],
	],
	"Tauren": [
		[
			Vector3(-0.48073, 0.71827, -0.50297),
			1.0, Color(0.0, 0.0, 0.0), 2.0, Color(0.65, 0.397645, 0.2727),
		],
		[
			Vector3(-0.49767, -0.78677, 0.36513),
			1.0, Color(0.0, 0.0, 0.0), 1.0, Color(0.6, 0.47059, 0.32471),
		],
	],
	"Scourge": [
		[
			Vector3(0.0, 0.0, -1.0),
			1.0, Color(0.2, 0.2, 0.2), 1.0, Color(0.0, 0.0, 0.0),
		],
	],
	"NightElf": [
		[
			Vector3(0.0, 0.0, -1.0),
			1.0, Color(0.0902, 0.0902, 0.1702), 1.0, Color(0.0, 0.0, 0.0),
		],
	],
	"Draenei": [
		[
			Vector3(0.61185, 0.62942, -0.47903),
			1.0, Color(0.0, 0.0, 0.0), 1.0, Color(0.56941, 0.52, 0.6),
		],
		[
			Vector3(-0.64345, -0.31052, -0.69968),
			1.0, Color(0.0, 0.0, 0.0), 1.0, Color(0.60941, 0.60392, 0.7),
		],
		[
			Vector3(-0.46481, -0.1432, 0.87376),
			1.0, Color(0.0, 0.0, 0.0), 2.0, Color(0.5835, 0.48941, 0.6),
		],
	],
	"BloodElf": [
		[
			Vector3(-0.82249, -0.54912, -0.14822),
			1.0, Color(0.0, 0.0, 0.0), 2.0, Color(0.581175, 0.50588, 0.42588),
		],
		[
			Vector3(0.0, 0.0, -1.0),
			1.0, Color(0.60392, 0.6149, 0.7), 1.0, Color(0.0, 0.0, 0.0),
		],
		[
			Vector3(0.02575, 0.86518, -0.50081),
			1.0, Color(0.0, 0.0, 0.0), 1.0, Color(0.59137, 0.51745, 0.63471),
		],
	],
	"DeathKnight": [
		[
			Vector3(0.0, 0.0, -1.0),
			1.0, Color(0.38824, 0.66353, 0.76941), 1.0, Color(0.0, 0.0, 0.0),
		],
	],
}
# CharModelGlowInfo from GlueParent.lua; other scenes glow at the default.
const SCENE_GLOW: Dictionary[String, float] = {"Human": 0.15, "Dwarf": 0.15}
const CHAR_BASE_INFO: String = "DBFilesClient\\CharBaseInfo.dbc"
const DBC_HEADER_SIZE: int = 20

static var _races: WowDBC
static var _classes: WowDBC
static var _race_classes: Dictionary[int, Array] = {}


static func race_order() -> Array[int]:
	return RACE_ORDER_WOTLK if String(WowLoader.profile()["id"]) == "wotlk" else RACE_ORDER


static func race_icon_column() -> float:
	return RACE_ICON_COLUMNS.get(String(WowLoader.profile()["id"]), 0.25)


static func race_name(race: int) -> String:
	return _race_string(race, "Name")


# The race's file token, such as "Scourge", which glue strings and scenes are keyed by.
static func race_file(race: int) -> String:
	return _race_string(race, "ClientFileString")


static func faction(race: int) -> Faction:
	var row: int = _race_table().find(race)
	var language: int = _race_table().get_uint(row, "BaseLanguage") if row >= 0 else 0
	return Faction.ALLIANCE if language == LANGUAGE_COMMON else Faction.HORDE


static func display_id(race: int, gender: Gender) -> int:
	var row: int = _race_table().find(race)
	if row < 0:
		return 0
	var column: String = "FemaleDisplayId" if gender == Gender.FEMALE else "MaleDisplayId"
	return _race_table().get_uint(row, column)


# The word the facial hair option goes by for this race and gender, such as "TUSKS".
static func facial_hair_kind(race: int, gender: Gender) -> String:
	var female: bool = gender == Gender.FEMALE
	return _race_string(
		race, "FacialHairCustomizationFemale" if female else "FacialHairCustomizationMale"
	)


static func hair_kind(race: int) -> String:
	return _race_string(race, "HairCustomization")


static func class_label(class_id: int) -> String:
	var row: int = _class_table().find(class_id)
	return _class_table().get_string(row, "Name") if row >= 0 else ""


static func class_file(class_id: int) -> String:
	var row: int = _class_table().find(class_id)
	return _class_table().get_string(row, "Filename") if row >= 0 else ""


# Classes the race may be, in CharBaseInfo order, which is the order of the class buttons.
static func classes_for(race: int) -> Array[int]:
	if _race_classes.is_empty():
		var data: PackedByteArray = WowAssets.archive.read(CHAR_BASE_INFO)
		for i: int in data.decode_u32(4):
			var pair: int = DBC_HEADER_SIZE + i * 2
			if not _race_classes.has(data[pair]):
				_race_classes[data[pair]] = []
			_race_classes[data[pair]].append(data[pair + 1])
	var classes: Array[int] = []
	classes.assign(_race_classes.get(race, []))
	return classes


static func scene_name(race: int) -> String:
	var file: String = race_file(race)
	return SCENE_STAND_INS.get(file, file)


# The stock select screen draws its scene unfogged; only character creation keeps the fog.
static func apply_scene(frame: WowModelFrame, race: int, fogged: bool = true) -> void:
	var scene: String = scene_name(race)
	frame.model_file = SCENE_PATH % [scene, scene]
	var fog: Array = SCENE_FOG.get(scene, [Color.BLACK, 0.0])
	frame.set_fog(fog[0], 0.0, fog[1] if fogged else 0.0)
	frame.glow = SCENE_GLOW.get(scene, WowModelFrame.DEFAULT_GLOW)
	var lights: Array[Dictionary] = []
	for light: Array in SCENE_LIGHTS.get(scene, []):
		lights.append({
			"direction": light[0],
			"ambient": light[2] * light[1],
			"diffuse": light[4] * light[3],
		})
	frame.set_scene_lights(lights)


# Glue scene cameras frame the native model; the display scale (tauren 1.35) is for the world.
static func character_model(look: Dictionary) -> Node3D:
	var display: int = display_id(look.get("race", 1), look.get("gender", Gender.MALE))
	var model: Node3D = WowAssets.creatures.instantiate(display, look)
	if model:
		model.scale = Vector3.ONE
	return model


static func _race_string(race: int, column: String) -> String:
	var row: int = _race_table().find(race)
	return _race_table().get_string(row, column) if row >= 0 else ""


static func _race_table() -> WowDBC:
	if _races == null:
		_races = WowDBC.open(WowAssets.archive, "ChrRaces")
	return _races


static func _class_table() -> WowDBC:
	if _classes == null:
		_classes = WowDBC.open(WowAssets.archive, "ChrClasses")
	return _classes
