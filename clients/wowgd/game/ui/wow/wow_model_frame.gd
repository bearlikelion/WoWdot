@tool
class_name WowModelFrame
extends TextureRect

# The glue scenes mark where the character stands with attachment 0.
const STAND_ATTACHMENT: int = 0

@export var model_file: String = "":
	set(value):
		if value == model_file:
			return
		model_file = value
		if is_node_ready():
			_load_scene()
@export var fog_near: float = 0.0
@export var fog_far: float = 0.0
@export var fog_color: Color = Color.BLACK

# Degrees the character turns from facing the camera, as SetCharacterSelectFacing takes them.
var facing: float = 0.0:
	set(value):
		facing = value
		_turn_character()

var _scene: Node3D
var _character: Node3D
var _stand: Vector3 = Vector3.ZERO
var _diagonal_fov: float = 0.0

@onready var _viewport: SubViewport = %Viewport
@onready var _camera: Camera3D = %Camera
@onready var _environment: Environment = (%Environment as WorldEnvironment).environment
@onready var _slot: Node3D = %Scene


func _ready() -> void:
	texture = _viewport.get_texture()
	_apply_fog()
	_load_scene()


# The glue parent and the window stretch both scale this rect; render at the pixels it covers.
func _process(_delta: float) -> void:
	var stretch: Vector2 = get_viewport().get_stretch_transform().get_scale()
	var pixels: Vector2i = Vector2i(
		(size * get_global_transform_with_canvas().get_scale() * stretch).round()
	)
	if pixels.x > 0 and pixels.y > 0 and pixels != _viewport.size:
		_viewport.size = pixels
		_fit_fov()


func set_fog(color: Color, near: float, far: float) -> void:
	fog_color = color
	fog_near = near
	fog_far = far
	_apply_fog()


func show_character(model: Node3D) -> void:
	if _character:
		_character.queue_free()
	_character = model
	if model:
		_slot.add_child(model)
		_turn_character()


func _load_scene() -> void:
	if _scene:
		_scene.queue_free()
		_scene = null
	if model_file.is_empty():
		return
	_scene = WowAssets.loader.load_m2(model_file)
	if _scene == null:
		return
	_slot.add_child(_scene)
	var info: Dictionary = WowAssets.loader.get_m2_info(model_file)
	var cameras: Array = info.get("cameras", [])
	if cameras.is_empty():
		return
	var view: Dictionary = cameras[0]
	_stand = view["target"]
	for attachment: Dictionary in info.get("attachments", []):
		if attachment["id"] == STAND_ATTACHMENT:
			_stand = attachment["position"]
	_diagonal_fov = view["fov"]
	_fit_fov()
	_camera.look_at_from_position(view["position"], view["target"])
	_turn_character()


# M2 cameras keep a diagonal FOV, so a wider frame sees a little more at the sides and less above.
func _fit_fov() -> void:
	if _diagonal_fov <= 0.0:
		return
	var aspect: float = float(_viewport.size.x) / _viewport.size.y
	_camera.fov = rad_to_deg(2.0 * atan(tan(_diagonal_fov / 2.0) / sqrt(1.0 + aspect * aspect)))


func _turn_character() -> void:
	if _character == null or not is_node_ready():
		return
	var toward_camera: Vector3 = _camera.position - _stand
	_character.position = _stand
	_character.rotation.y = atan2(-toward_camera.x, -toward_camera.z) + deg_to_rad(facing)


func _apply_fog() -> void:
	if not is_node_ready():
		return
	_environment.fog_enabled = fog_far > 0.0
	_environment.fog_light_color = fog_color
	_environment.fog_depth_begin = fog_near
	_environment.fog_depth_end = fog_far
