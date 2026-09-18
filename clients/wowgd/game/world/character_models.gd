class_name CharacterModels
extends RefCounted

enum Section { SKIN, FACE, FACIAL_HAIR, HAIR, UNDERWEAR }
enum TextureSlot { BODY = 1, HAIR = 6 }

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

var _loader: WowLoader
var _sections: WowDBC
var _hair_geosets: WowDBC
var _facial_hair: WowDBC
var _section_rows: Dictionary[int, Array] = {}
var _skins: Dictionary[String, ImageTexture] = {}


func _init(loader: WowLoader) -> void:
	_loader = loader
	_sections = WowDBC.open(loader.archive, "CharSections")
	_hair_geosets = WowDBC.open(loader.archive, "CharHairGeosets")
	_facial_hair = WowDBC.open(loader.archive, "CharacterFacialHairStyles")


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
	var hair: String = _texture(
		race, gender, Section.HAIR, look.get("hair_style", 0), look.get("hair_color", 0)
	)
	if not hair.is_empty():
		skins[TextureSlot.HAIR] = hair
	return _loader.load_m2(model_path, skins, _geosets(race, gender, look))


static func player_look(session: WowSession, guid: int) -> Dictionary:
	var bytes_0: int = session.get_field(guid, "UNIT_FIELD_BYTES_0")
	var player_bytes: int = session.get_field(guid, "PLAYER_BYTES")
	var player_bytes_2: int = session.get_field(guid, "PLAYER_BYTES_2")
	return {
		"race": bytes_0 & 0xFF,
		"gender": (bytes_0 >> 16) & 0xFF,
		"skin": player_bytes & 0xFF,
		"face": (player_bytes >> 8) & 0xFF,
		"hair_style": (player_bytes >> 16) & 0xFF,
		"hair_color": (player_bytes >> 24) & 0xFF,
		"facial_hair": player_bytes_2 & 0xFF,
	}


func _skin(race: int, gender: int, look: Dictionary) -> ImageTexture:
	var skin: int = look.get("skin", 0)
	var hair_color: int = look.get("hair_color", 0)
	var key: String = "%d_%d_%d_%d_%d_%d_%d" % [
		race, gender, skin, look.get("face", 0), look.get("hair_style", 0), hair_color,
		look.get("facial_hair", 0),
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
	# The first hair texture is the hair itself; the scalp overlays that follow match a region.
	overlays.append_array(_textures(race, gender, Section.HAIR, look.get("hair_style", 0), hair_color))
	overlays.append_array(_textures(race, gender, Section.UNDERWEAR, -1, skin))
	var scale: int = maxi(base.get_width() / SKIN_ATLAS_SIZE, 1)
	for path: String in overlays:
		var region: Vector2i = _region(path)
		var overlay: Image = _loader.load_image(path) if region != -Vector2i.ONE else null
		if overlay == null:
			continue
		overlay = overlay.duplicate()
		overlay.clear_mipmaps()
		base.blend_rect(overlay, Rect2i(Vector2i.ZERO, overlay.get_size()), region * scale)
	base.generate_mipmaps()
	_skins[key] = ImageTexture.create_from_image(base)
	return _skins[key]


func _region(path: String) -> Vector2i:
	var name: String = path.to_lower().get_file()
	for word: String in SKIN_REGIONS:
		if name.contains(word):
			return SKIN_REGIONS[word]
	return -Vector2i.ONE


func _texture(race: int, gender: int, section: Section, variation: int, color: int) -> String:
	var found: PackedStringArray = _textures(race, gender, section, variation, color)
	return found[0] if not found.is_empty() else ""


# A variation of -1 matches any variation; each matching row may carry up to three textures.
func _textures(
	race: int, gender: int, section: Section, variation: int, color: int,
) -> PackedStringArray:
	var found: PackedStringArray = []
	for row: int in _rows(race, gender):
		if _sections.get_uint(row, "BaseSection") != section:
			continue
		if _sections.get_uint(row, "ColorIndex") != color:
			continue
		if variation >= 0 and _sections.get_uint(row, "VariationIndex") != variation:
			continue
		for column: String in ["Texture1", "Texture2", "Texture3"]:
			var path: String = _sections.get_string(row, column)
			if not path.is_empty():
				found.append(path)
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
	return geosets
