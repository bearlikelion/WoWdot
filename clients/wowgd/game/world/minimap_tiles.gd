class_name MinimapTiles
extends RefCounted

const TRANSLATE: String = "textures\\Minimap\\md5translate.trs"
const FOLDER: String = "textures\\Minimap\\"

# "azeroth\map32_48.blp" style keys to the hashed file the client stores the tile under.
static var _files: Dictionary[String, String] = {}
static var _textures: Dictionary[String, WowTexture] = {}


# The minimap image for one ADT tile, or null where the map has none.
static func texture(map_dir: String, tile: Vector2i) -> WowTexture:
	if _files.is_empty():
		_load()
	var key: String = ("%s\\map%d_%d.blp" % [map_dir, tile.x, tile.y]).to_lower()
	if not _files.has(key):
		return null
	if not _textures.has(key):
		var image: WowTexture = WowTexture.new()
		image.file = FOLDER + _files[key]
		_textures[key] = image
	return _textures[key]


static func _load() -> void:
	var text: String = WowLoader.get_shared().archive.read(TRANSLATE).get_string_from_ascii()
	for line: String in text.split("\n"):
		var parts: PackedStringArray = line.strip_edges().split("\t")
		if parts.size() == 2:
			_files[parts[0].to_lower()] = parts[1]
