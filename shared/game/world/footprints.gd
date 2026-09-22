class_name Footprints
extends Node3D

# CreatureModelData.dbc: the FootprintTextures row and the print's size in inches.
const FOOTPRINT_COLUMN: int = 6
const LENGTH_COLUMN: int = 7
const WIDTH_COLUMN: int = 8
const TEXTURE_COLUMN: int = 1
const POOL: int = 48
const FADE_SECONDS: float = 12.0
const DECAL_DEPTH: float = 1.0
const INCHES_PER_YARD: float = 36.0

static var _models: WowDBC
static var _textures: WowDBC
static var _art: Dictionary[int, Texture2D] = {}

var _pool: Array[Decal] = []
var _next: int = 0
var _left: bool = false


func _ready() -> void:
	_models = WowDBC.open(WowAssets.archive, "CreatureModelData")
	_textures = WowDBC.open(WowAssets.archive, "FootprintTextures")
	for i: int in POOL:
		var decal: Decal = Decal.new()
		decal.visible = false
		decal.cull_mask = 1
		add_child(decal)
		_pool.append(decal)


func _process(delta: float) -> void:
	for decal: Decal in _pool:
		if decal.visible:
			decal.albedo_mix -= delta / FADE_SECONDS
			decal.visible = decal.albedo_mix > 0.0


# Stamps one print under the unit's model, alternating feet across the model's width.
func stamp(model_id: int, at: Vector3, heading: float) -> void:
	var row: int = _models.find(model_id)
	if row < 0:
		return
	var print_id: int = _models.get_uint(row, FOOTPRINT_COLUMN)
	if print_id == 0:
		return
	var art: Texture2D = _texture(print_id)
	if art == null:
		return
	var decal: Decal = _pool[_next]
	_next = (_next + 1) % POOL
	var length: float = _models.get_float(row, LENGTH_COLUMN) / INCHES_PER_YARD
	var width: float = _models.get_float(row, WIDTH_COLUMN) / INCHES_PER_YARD
	if length <= 0.0 or width <= 0.0:
		return
	decal.texture_albedo = art
	decal.size = Vector3(width, DECAL_DEPTH, length)
	decal.albedo_mix = 1.0
	decal.modulate = Color.WHITE
	var side: Vector3 = Vector3(cos(heading), 0.0, -sin(heading)) * width * (0.5 if _left else -0.5)
	_left = not _left
	decal.global_transform = Transform3D(Basis(Vector3.UP, heading), at + side)
	decal.visible = true


static func _texture(print_id: int) -> Texture2D:
	if not _art.has(print_id):
		var row: int = _textures.find(print_id)
		var art: Texture2D = null
		if row >= 0:
			# A decal needs an engine texture; the archive backed one never reaches the decal atlas.
			art = WowAssets.loader.load_texture(_textures.get_string(row, TEXTURE_COLUMN) + ".blp")
		_art[print_id] = art
	return _art[print_id]
