class_name CharacterModels
extends RefCounted

enum Section { SKIN, FACE, FACIAL_HAIR, HAIR, UNDERWEAR }
enum Option { SKIN, FACE, HAIR_STYLE, HAIR_COLOR, FACIAL_HAIR }
enum EquipSlot { HEAD, SHOULDER, SHIRT, CHEST, WAIST, LEGS, FEET, WRIST, HANDS, TABARD }
# FUR is the skin's second texture, which tauren wear on their manes, beards and body tufts.
enum TextureSlot { BODY = 1, CAPE = 2, HAIR = 6, FUR = 8 }

const SKIN_ATLAS_SIZE: int = 256
# Where each overlay lands on the 256x256 body skin, matched by a word in its file name.
const SKIN_REGIONS: Dictionary[String, Vector2i] = {
	"upper": Vector2i(0, 160),
	"lower": Vector2i(0, 192),
	"pelvis": Vector2i(128, 96),
	"torso": Vector2i(128, 0),
}
# Bare hands, feet and legs, ears, and 1501 (no cloak), which also carries the neck and upper chest.
const BARE_GEOSETS: Array[int] = [0, 401, 501, 702, 1301, 1501]
const BAKED_TEXTURES: String = "Textures\\BakedNpcTextures\\"
const TEXTURE_COLUMNS: PackedStringArray = ["Texture1", "Texture2", "Texture3"]
const SCALP_COLUMNS: PackedStringArray = ["Texture2", "Texture3"]
# Body geoset group an item's first GeosetGroup picks from, per equipment slot.
const SLOT_GEOSET_GROUPS: Dictionary[EquipSlot, int] = {
	EquipSlot.HANDS: 400, EquipSlot.FEET: 500, EquipSlot.CHEST: 800, EquipSlot.WRIST: 800,
	EquipSlot.LEGS: 1300, EquipSlot.TABARD: 1200,
}
# Inventory slots (PLAYER_VISIBLE_ITEM order) that dress the body.
const INVENTORY_SLOTS: Dictionary[int, EquipSlot] = {
	0: EquipSlot.HEAD, 2: EquipSlot.SHOULDER, 3: EquipSlot.SHIRT, 4: EquipSlot.CHEST,
	5: EquipSlot.WAIST, 6: EquipSlot.LEGS, 7: EquipSlot.FEET, 8: EquipSlot.WRIST,
	9: EquipSlot.HANDS, 18: EquipSlot.TABARD,
}
const VISIBLE_ITEM_STRIDE: int = 12
# PLAYER_FLAGS the server sets from CMSG_SHOWING_HELM and CMSG_SHOWING_CLOAK.
const PLAYER_FLAG_HIDE_HELM: int = 0x400
const PLAYER_FLAG_HIDE_CLOAK: int = 0x800
# PLAYER_VISIBLE_ITEM slots of the main hand, off hand and ranged weapon, and of the cloak.
const WEAPON_SLOTS: Array[int] = [15, 16, 17]
const BACK_SLOT: int = 14
const CAPES: String = "Item\\ObjectComponents\\Cape\\"
# CharStartOutfit.dbc packs race, class and gender into one key and holds twelve slots.
const OUTFIT_KEY_COLUMN: int = 1
const OUTFIT_DISPLAY_COLUMN: int = 14
const OUTFIT_TYPE_COLUMN: int = 26
const OUTFIT_SLOTS: int = 12
const OUTFIT_EQUIPMENT_SLOTS: int = 19
# An item's inventory type and the equipment slot it fills.
const OUTFIT_SLOT_OF: Dictionary[int, int] = {
	1: 0, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6, 8: 7, 9: 8, 10: 9, 13: 15, 14: 16, 15: 17,
	16: 14, 17: 15, 19: 18, 20: 4, 21: 15, 22: 16, 23: 16, 25: 17, 26: 17,
}
# Later slots paint over earlier ones on the body skin.
const ITEM_DRAW_ORDER: Array[EquipSlot] = [
	EquipSlot.SHIRT, EquipSlot.LEGS, EquipSlot.FEET, EquipSlot.CHEST, EquipSlot.WAIST,
	EquipSlot.WRIST, EquipSlot.HANDS, EquipSlot.TABARD,
]
# ItemDisplayInfo texture column, its TextureComponents folder and its rectangle on the skin.
const ITEM_REGIONS: Dictionary[String, Array] = {
	"TextureArmUpper": ["ArmUpperTexture", Rect2i(0, 0, 128, 64)],
	"TextureArmLower": ["ArmLowerTexture", Rect2i(0, 64, 128, 64)],
	"TextureHand": ["HandTexture", Rect2i(0, 128, 128, 32)],
	"TextureTorsoUpper": ["TorsoUpperTexture", Rect2i(128, 0, 128, 64)],
	"TextureTorsoLower": ["TorsoLowerTexture", Rect2i(128, 64, 128, 32)],
	"TextureLegUpper": ["LegUpperTexture", Rect2i(128, 96, 128, 64)],
	"TextureLegLower": ["LegLowerTexture", Rect2i(128, 160, 128, 64)],
	"TextureFoot": ["FootTexture", Rect2i(128, 224, 128, 32)],
}
const TEXTURE_COMPONENTS: String = "Item\\TextureComponents\\"
# HelmetGeosetVisData columns, each a mask of the races whose geoset group the helmet hides.
const HELMET_HIDES: Dictionary[String, int] = {
	"Hair": 0, "Facial1": 100, "Facial2": 200, "Facial3": 300, "Ears": 700,
}

var item_models: ItemModels

var _loader: WowLoader
var _sections: WowDBC
var _hair_geosets: WowDBC
var _facial_hair: WowDBC
var _item_displays: WowDBC
static var _outfits: WowDBC
var _helmet_vis: WowDBC
var _section_rows: Dictionary[int, Array] = {}
var _skins: Dictionary[String, ImageTexture] = {}


func _init(loader: WowLoader) -> void:
	_loader = loader
	_sections = WowDBC.open(loader.archive, "CharSections")
	_hair_geosets = WowDBC.open(loader.archive, "CharHairGeosets")
	_facial_hair = WowDBC.open(loader.archive, "CharacterFacialHairStyles")
	_item_displays = WowDBC.open(loader.archive, "ItemDisplayInfo")
	_helmet_vis = WowDBC.open(loader.archive, "HelmetGeosetVisData")
	item_models = ItemModels.new(loader)


# The look is race, gender, skin, face, hair_style, hair_color and facial_hair; "baked" names an
# NPC's pre-composited skin under BakedNpcTextures.
func instantiate(model_path: String, look: Dictionary) -> Node3D:
	var race: int = look.get("race", 1)
	var gender: int = look.get("gender", 0)
	var skins: Dictionary = {}
	var baked: String = look.get("baked", "")
	if baked.is_empty():
		var skin: ImageTexture = _skin(race, gender, look)
		if skin:
			skins[TextureSlot.BODY] = skin
	else:
		skins[TextureSlot.BODY] = BAKED_TEXTURES + baked
	var hair_color: int = look.get("hair_color", 0)
	var hair: String = _texture(race, gender, Section.HAIR, look.get("hair_style", 0), hair_color)
	# Bald styles have no hair texture, but their facial hair still wears the colour.
	if hair.is_empty():
		hair = _texture(race, gender, Section.HAIR, -1, hair_color)
	if not hair.is_empty():
		skins[TextureSlot.HAIR] = hair
	var skin_textures: PackedStringArray = _textures(
		race, gender, Section.SKIN, -1, look.get("skin", 0)
	)
	if skin_textures.size() > 1:
		skins[TextureSlot.FUR] = skin_textures[1]
	var cape: int = _item_displays.find(look.get("cape", 0)) if look.get("cape", 0) != 0 else -1
	if cape >= 0:
		var cape_texture: String = _item_displays.get_string(cape, "LeftModelTexture")
		skins[TextureSlot.CAPE] = CAPES + cape_texture + ".blp"
	var model: Node3D = _loader.load_m2(model_path, skins, _geosets(race, gender, look))
	if model:
		_attach_items(model, model_path, look)
	return model


# "pending" is true while item queries for the gear are still out; ask again on item_info_received.
static func player_look(session: WowSession, guid: int) -> Dictionary:
	var bytes_0: int = session.get_field(guid, "UNIT_FIELD_BYTES_0")
	var player_bytes: int = session.get_field(guid, "PLAYER_BYTES")
	var player_bytes_2: int = session.get_field(guid, "PLAYER_BYTES_2")
	var equipment: PackedInt32Array = []
	equipment.resize(EquipSlot.size())
	var pending: bool = false
	var items: PackedInt32Array = visible_items(session, guid)
	for inventory_slot: int in INVENTORY_SLOTS:
		if items[inventory_slot] == 0:
			continue
		var info: Dictionary = session.get_item_info(items[inventory_slot])
		pending = pending or info.is_empty()
		equipment[INVENTORY_SLOTS[inventory_slot]] = info.get("display_id", 0)
	var weapons: Array[ItemModels.Weapon] = []
	for inventory_slot: int in WEAPON_SLOTS:
		var entry: int = items[inventory_slot]
		var info: Dictionary = session.get_item_info(entry) if entry != 0 else {}
		pending = pending or (entry != 0 and info.is_empty())
		weapons.append(ItemModels.Weapon.new(
			info.get("display_id", 0), info.get("sheath", 0), info.get("subclass", 0)
		))
	var flags: int = session.get_field(guid, "PLAYER_FLAGS")
	if flags & PLAYER_FLAG_HIDE_HELM:
		equipment[EquipSlot.HEAD] = 0
	var cloak: int = 0 if flags & PLAYER_FLAG_HIDE_CLOAK else items[BACK_SLOT]
	var cloak_info: Dictionary = session.get_item_info(cloak) if cloak != 0 else {}
	pending = pending or (cloak != 0 and cloak_info.is_empty())
	return {
		"race": bytes_0 & 0xFF,
		"gender": (bytes_0 >> 16) & 0xFF,
		"skin": player_bytes & 0xFF,
		"face": (player_bytes >> 8) & 0xFF,
		"hair_style": (player_bytes >> 16) & 0xFF,
		"hair_color": (player_bytes >> 24) & 0xFF,
		"facial_hair": player_bytes_2 & 0xFF,
		"equipment": equipment,
		"weapons": weapons,
		"sheath_state": ItemModels.sheath_state(session, guid),
		"cape": cloak_info.get("display_id", 0),
		"pending": pending,
	}


# How many of an option character creation cycles through, given the look's other choices.
func option_count(look: Dictionary, option: Option) -> int:
	var race: int = look.get("race", 1)
	var gender: int = look.get("gender", 0)
	var found: Dictionary[int, bool] = {}
	if option == Option.FACIAL_HAIR:
		for row: int in _facial_hair.row_count():
			if _facial_hair.get_uint(row, "RaceID") == race \
			and _facial_hair.get_uint(row, "SexID") == gender:
				found[_facial_hair.get_uint(row, "Variation")] = true
		return found.size()
	for row: int in _rows(race, gender):
		# Flagged rows are NPC-only looks.
		if _sections.get_uint(row, "Flags") != 0:
			continue
		var section: int = _sections.get_uint(row, "BaseSection")
		var variation: int = _sections.get_uint(row, "VariationIndex")
		var color: int = _sections.get_uint(row, "ColorIndex")
		match option:
			Option.SKIN:
				if section == Section.SKIN:
					found[color] = true
			Option.FACE:
				if section == Section.FACE and color == look.get("skin", 0):
					found[variation] = true
			Option.HAIR_STYLE:
				if section == Section.HAIR:
					found[variation] = true
			Option.HAIR_COLOR:
				if section == Section.HAIR and variation == look.get("hair_style", 0):
					found[color] = true
	return found.size()


# The look of a character from SMSG_CHAR_ENUM, whose gear arrives as display ids.
static func listed_look(character: Dictionary) -> Dictionary:
	var displays: PackedInt32Array = character.get("equipment", PackedInt32Array())
	var equipment: PackedInt32Array = []
	equipment.resize(EquipSlot.size())
	for inventory_slot: int in INVENTORY_SLOTS:
		if inventory_slot < displays.size():
			equipment[INVENTORY_SLOTS[inventory_slot]] = displays[inventory_slot]
	var weapons: Array[ItemModels.Weapon] = []
	for inventory_slot: int in WEAPON_SLOTS:
		var display: int = displays[inventory_slot] if inventory_slot < displays.size() else 0
		weapons.append(ItemModels.Weapon.new(display))
	var look: Dictionary = character.duplicate()
	look["equipment"] = equipment
	look["weapons"] = weapons
	look["cape"] = displays[BACK_SLOT] if BACK_SLOT < displays.size() else 0
	return look


# The gear CharStartOutfit.dbc creates a character in, for the preview on the create screen.
static func starting_look(look: Dictionary) -> Dictionary:
	if _outfits == null:
		_outfits = WowDBC.open(WowAssets.archive, "CharStartOutfit")
	var wanted: int = int(look.get("race", 0)) \
	| (int(look.get("class", 0)) << 8) | (int(look.get("gender", 0)) << 16)
	var displays: PackedInt32Array = []
	displays.resize(OUTFIT_EQUIPMENT_SLOTS)
	for row: int in _outfits.row_count():
		if _outfits.get_uint(row, OUTFIT_KEY_COLUMN) & 0xFFFFFF != wanted:
			continue
		for slot: int in OUTFIT_SLOTS:
			var kind: int = _outfits.get_int(row, OUTFIT_TYPE_COLUMN + slot)
			var display: int = _outfits.get_int(row, OUTFIT_DISPLAY_COLUMN + slot)
			if display > 0 and OUTFIT_SLOT_OF.has(kind):
				displays[OUTFIT_SLOT_OF[kind]] = display
		break
	var dressed: Dictionary = look.duplicate()
	dressed["equipment"] = displays
	return listed_look(dressed)


# Item entries per inventory slot, from the PLAYER_VISIBLE_ITEM_n_0 fields.
static func visible_items(session: WowSession, guid: int) -> PackedInt32Array:
	var first: int = session.field_index("PLAYER_VISIBLE_ITEM_1_0")
	var items: PackedInt32Array = []
	for slot: int in 19:
		items.append(session.get_field(guid, first + slot * VISIBLE_ITEM_STRIDE))
	return items


func _skin(race: int, gender: int, look: Dictionary) -> ImageTexture:
	var skin: int = look.get("skin", 0)
	var hair_color: int = look.get("hair_color", 0)
	var key: String = "%d_%d_%d_%d_%d_%d_%d_%s" % [
		race, gender, skin, look.get("face", 0), look.get("hair_style", 0), hair_color,
		look.get("facial_hair", 0), look.get("equipment", PackedInt32Array()),
	]
	if _skins.has(key):
		return _skins[key]
	var base_path: String = _texture(race, gender, Section.SKIN, -1, skin)
	if base_path.is_empty():
		return null
	var base: Image = _loader.load_image(base_path)
	if base == null:
		return null
	base = base.duplicate()
	base.clear_mipmaps()
	var overlays: PackedStringArray = []
	overlays.append_array(_textures(race, gender, Section.FACE, look.get("face", 0), skin))
	overlays.append_array(
		_textures(race, gender, Section.FACIAL_HAIR, look.get("facial_hair", 0), hair_color)
	)
	# Texture1 is the hair itself, and a stray FaceLower on tauren; only scalp textures overlay.
	overlays.append_array(
		_textures(race, gender, Section.HAIR, look.get("hair_style", 0), hair_color, SCALP_COLUMNS)
	)
	overlays.append_array(_textures(race, gender, Section.UNDERWEAR, -1, skin))
	var scale: int = maxi(floori(base.get_width() / float(SKIN_ATLAS_SIZE)), 1)
	for path: String in overlays:
		var region: Vector2i = _region(path)
		var overlay: Image = _loader.load_image(path) if region != -Vector2i.ONE else null
		if overlay == null:
			continue
		overlay = overlay.duplicate()
		overlay.clear_mipmaps()
		base.blend_rect(overlay, Rect2i(Vector2i.ZERO, overlay.get_size()), region * scale)
	_paint_equipment(base, gender, look.get("equipment", PackedInt32Array()), scale)
	base.generate_mipmaps()
	_skins[key] = ImageTexture.create_from_image(base)
	return _skins[key]


# Helmet, shoulders and weapons are models of their own, hung on the body's attachment points.
func _attach_items(model: Node3D, model_path: String, look: Dictionary) -> void:
	var race: int = look.get("race", 1)
	var gender: int = look.get("gender", 0)
	var equipment: PackedInt32Array = look.get("equipment", PackedInt32Array())
	if equipment.size() > EquipSlot.SHOULDER:
		var helmet: int = equipment[EquipSlot.HEAD]
		item_models.attach(model, model_path, ItemModels.Slot.HEAD, helmet, race, gender)
		var shoulders: int = equipment[EquipSlot.SHOULDER]
		item_models.attach(model, model_path, ItemModels.Slot.SHOULDERS, shoulders)
	var state: ItemModels.SheathState = look.get("sheath_state", ItemModels.SheathState.MELEE)
	item_models.arm(model, model_path, look.get("weapons", []), state)


func _paint_equipment(skin: Image, gender: int, equipment: PackedInt32Array, scale: int) -> void:
	for slot: EquipSlot in ITEM_DRAW_ORDER:
		var row: int = _item_displays.find(equipment[slot]) if slot < equipment.size() else -1
		if row < 0:
			continue
		for column: String in ITEM_REGIONS:
			var texture_name: String = _item_displays.get_string(row, column)
			if texture_name.is_empty():
				continue
			var region: Rect2i = ITEM_REGIONS[column][1]
			var image: Image = _item_texture(ITEM_REGIONS[column][0], texture_name, gender)
			if image == null:
				continue
			image = image.duplicate()
			image.clear_mipmaps()
			if image.get_size() != region.size * scale:
				image.resize(region.size.x * scale, region.size.y * scale)
			skin.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), region.position * scale)


# Component textures come per gender (_M, _F) or shared (_U).
func _item_texture(folder: String, texture_name: String, gender: int) -> Image:
	var base: String = TEXTURE_COMPONENTS + folder + "\\" + texture_name
	for suffix: String in ["_F" if gender == 1 else "_M", "_U"]:
		if _loader.archive.has(base + suffix + ".blp"):
			return _loader.load_image(base + suffix + ".blp")
	return null


func _region(path: String) -> Vector2i:
	var name: String = path.to_lower().get_file()
	for word: String in SKIN_REGIONS:
		if name.contains(word):
			return SKIN_REGIONS[word]
	return -Vector2i.ONE


func _texture(race: int, gender: int, section: Section, variation: int, color: int) -> String:
	var found: PackedStringArray = _textures(race, gender, section, variation, color)
	return found[0] if not found.is_empty() else ""


# A variation of -1 matches any variation that has textures; a row carries up to three.
func _textures(
	race: int, gender: int, section: Section, variation: int, color: int,
	columns: PackedStringArray = TEXTURE_COLUMNS,
) -> PackedStringArray:
	var found: PackedStringArray = []
	for row: int in _rows(race, gender):
		if _sections.get_uint(row, "BaseSection") != section:
			continue
		if _sections.get_uint(row, "ColorIndex") != color:
			continue
		if variation >= 0 and _sections.get_uint(row, "VariationIndex") != variation:
			continue
		for column: String in columns:
			var path: String = _sections.get_string(row, column)
			if not path.is_empty():
				found.append(path)
		if variation >= 0 or not found.is_empty():
			break
	return found


func _rows(race: int, gender: int) -> Array:
	var key: int = race * 2 + gender
	if not _section_rows.has(key):
		var rows: Array = []
		for row: int in _sections.row_count():
			if _sections.get_uint(row, "RaceID") == race and _sections.get_uint(row, "SexID") == gender:
				rows.append(row)
		_section_rows[key] = rows
	return _section_rows[key]


func _geosets(race: int, gender: int, look: Dictionary) -> PackedInt32Array:
	var geosets: PackedInt32Array = PackedInt32Array(BARE_GEOSETS)
	var scalp: int = 1
	for row: int in _hair_geosets.row_count():
		if _hair_geosets.get_uint(row, "RaceID") == race \
		and _hair_geosets.get_uint(row, "SexID") == gender \
		and _hair_geosets.get_uint(row, "Variation") == look.get("hair_style", 0):
			scalp = maxi(_hair_geosets.get_uint(row, "GeosetID"), 1)
			break
	geosets.append(scalp)
	var facial: Vector3i = Vector3i.ONE
	for row: int in _facial_hair.row_count():
		if _facial_hair.get_uint(row, "RaceID") == race \
		and _facial_hair.get_uint(row, "SexID") == gender \
		and _facial_hair.get_uint(row, "Variation") == look.get("facial_hair", 0):
			facial = Vector3i(
				maxi(_facial_hair.get_uint(row, "Geoset100"), 1),
				maxi(_facial_hair.get_uint(row, "Geoset200"), 1),
				maxi(_facial_hair.get_uint(row, "Geoset300"), 1),
			)
			break
	geosets.append_array([100 + facial.x, 200 + facial.y, 300 + facial.z])
	var equipment: PackedInt32Array = look.get("equipment", PackedInt32Array())
	for slot: EquipSlot in SLOT_GEOSET_GROUPS:
		if slot < equipment.size() and equipment[slot] != 0:
			var least: int = 1 if slot == EquipSlot.TABARD else 0
			_equip_geoset(geosets, SLOT_GEOSET_GROUPS[slot], equipment[slot], least)
	if look.get("cape", 0) != 0:
		_equip_geoset(geosets, 1500, look["cape"], 1)
	_hide_under_helmet(geosets, race, gender, equipment)
	return geosets


# A helmet swaps the groups it covers for their bare geoset: bald, beardless, earless.
func _hide_under_helmet(
	geosets: PackedInt32Array, race: int, gender: int, equipment: PackedInt32Array,
) -> void:
	if equipment.size() <= EquipSlot.HEAD or equipment[EquipSlot.HEAD] == 0:
		return
	var item: int = _item_displays.find(equipment[EquipSlot.HEAD])
	var vis_column: String = "HelmetGeosetVis%d" % gender
	var vis_id: int = _item_displays.get_uint(item, vis_column) if item >= 0 else 0
	var vis: int = _helmet_vis.find(vis_id) if vis_id > 0 else -1
	if vis < 0:
		return
	for column: String in HELMET_HIDES:
		if (_helmet_vis.get_uint(vis, column) & (1 << race)) == 0:
			continue
		var group: int = HELMET_HIDES[column]
		for i: int in range(geosets.size() - 1, -1, -1):
			if geosets[i] != 0 and _geoset_group(geosets[i]) == _geoset_group(group):
				geosets.remove_at(i)
		geosets.append(group + 1)


# Swaps the group's current geoset for the item's; tabards and cloaks show even at variant 0.
func _equip_geoset(geosets: PackedInt32Array, group: int, display_id: int, least: int = 0) -> void:
	var row: int = _item_displays.find(display_id)
	if row < 0:
		return
	var variant: int = maxi(_item_displays.get_uint(row, "GeosetGroup1"), least)
	if variant == 0:
		return
	for i: int in range(geosets.size() - 1, -1, -1):
		if _geoset_group(geosets[i]) == _geoset_group(group):
			geosets.remove_at(i)
	geosets.append(group + 1 + variant)


# Geoset ids are the group times 100 plus the variant.
static func _geoset_group(geoset: int) -> int:
	return floori(geoset / 100.0)
