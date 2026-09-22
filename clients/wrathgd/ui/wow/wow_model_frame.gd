@tool
class_name WowModelFrame
extends TextureRect

enum LightType { DIRECTIONAL, POINT }

# The glue scenes mark where the character stands with attachment 0.
const STAND_ATTACHMENT: int = 0
# PlayerModel frames without a scene show the whole character, a little clear of the edges.
const CHARACTER_FOV: float = 30.0
const DESIGN_ASPECT: float = 4.0 / 3.0
const CHARACTER_MARGIN: float = 1.15

@export var model_file: String = "":
	set(value):
		if value == model_file:
			return
		model_file = value
		if is_node_ready():
			_load_scene()
# The stock falloff is 1 / (0.7 d + 0.03 d * d) with no cutoff; this range and curve sit close to it.
const POINT_REACH: float = 4.0
const POINT_FALLOFF: float = 1.0
# GlueParent.lua's SetLighting passes 0.3 where a screen names no glow of its own.
const DEFAULT_GLOW: float = 0.3

# SetGlow's value: how much the scene's bright parts bloom, not how brightly it is lit.
@export var glow: float = DEFAULT_GLOW:
	set(value):
		glow = value
		_apply_glow()

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
@onready var _default_light: DirectionalLight3D = %Light


func _ready() -> void:
	texture = _viewport.get_texture()
	_apply_fog()
	_apply_glow()
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


# A PlayerModel with no scene: the character alone, whole and facing the camera, over the frame art.
func frame_character(model: Node3D) -> void:
	_viewport.transparent_bg = true
	_environment.background_mode = Environment.BG_CLEAR_COLOR
	_stand = Vector3.ZERO
	show_character(model)
	if model == null:
		return
	var bounds: AABB = AABB()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = model.transform * mesh.get_aabb()
		bounds = bounds.merge(box) if bounds.has_volume() else box
	var center: Vector3 = bounds.get_center()
	var half_fov: float = deg_to_rad(CHARACTER_FOV) / 2.0
	var distance: float = bounds.size.y / 2.0 / tan(half_fov) * CHARACTER_MARGIN
	_diagonal_fov = 0.0
	_camera.fov = CHARACTER_FOV
	_camera.look_at_from_position(center + Vector3(0.0, 0.0, distance), center)
	_turn_character()


func _load_scene() -> void:
	if _scene:
		_scene.queue_free()
		_scene = null
	_default_light.show()
	if model_file.is_empty():
		return
	_scene = WowAssets.loader.load_m2(model_file)
	if _scene == null:
		return
	_slot.add_child(_scene)
	# The scene's own sequence drives the sky, the snow and the wyrm's flight past the citadel.
	var player: AnimationPlayer = _scene.get_node_or_null("AnimationPlayer")
	if player != null and not player.get_animation_list().is_empty():
		player.play(player.get_animation_list()[0])
	var info: Dictionary = WowAssets.loader.get_m2_info(model_file)
	_light_scene(info.get("lights", []))
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


# The scene's authored lights replace the frame's own, as the stock glue screens are lit.
func _light_scene(lights: Array) -> void:
	if lights.is_empty():
		return
	_default_light.hide()
	var skeleton: Skeleton3D = _scene.find_children("*", "Skeleton3D", true, false).pop_front()
	var ambient: Color = Color.BLACK
	for light: Dictionary in lights:
		ambient += light["ambient"]
	ambient = Color(ambient, 1.0).clamp()
	for light: Dictionary in lights:
		var diffuse: Color = light["diffuse"]
		var peak: float = maxf(diffuse.r, maxf(diffuse.g, diffuse.b))
		if peak <= 0.0:
			continue
		var lamp: Light3D
		if light["type"] == LightType.POINT:
			lamp = OmniLight3D.new()
			lamp.light_color = Color(diffuse.r / peak, diffuse.g / peak, diffuse.b / peak)
			# The stock client sums light in gamma space, so an over-bright colour scales as a power.
			lamp.light_energy = pow(peak, 2.2)
		else:
			lamp = DirectionalLight3D.new()
			# Stock clamps ambient plus diffuse to white, so an over-bright sun only fills what is left.
			var lit: Color = (ambient + Color(diffuse, 0.0)).clamp()
			var fill: Color = lit.srgb_to_linear() - ambient.srgb_to_linear()
			lamp.light_color = Color(fill, 1.0).linear_to_srgb()
		lamp.light_specular = 0.0
		var mount: Node3D = _scene
		var origin: Vector3 = Vector3.ZERO
		if skeleton and light["bone"] >= 0 and light["bone"] < skeleton.get_bone_count():
			var attachment: BoneAttachment3D = BoneAttachment3D.new()
			attachment.bone_idx = light["bone"]
			skeleton.add_child(attachment)
			mount = attachment
			# An M2 light's position is model space, like the bone's pivot.
			origin = skeleton.get_bone_global_rest(light["bone"]).origin
		mount.add_child(lamp)
		if lamp is OmniLight3D:
			lamp.position = light["position"] - origin
			lamp.omni_range = light["attenuation_end"] * POINT_REACH
			lamp.omni_attenuation = POINT_FALLOFF
		else:
			# A directional M2 light shines down its bone's up axis.
			lamp.basis = Basis(Vector3.RIGHT, -PI / 2.0)
	_environment.ambient_light_color = ambient


# An M2 camera keeps a diagonal FOV framed for the 4:3 screen; a wider window sees more at the sides.
func _fit_fov() -> void:
	if _diagonal_fov <= 0.0:
		return
	var diagonal: float = sqrt(1.0 + DESIGN_ASPECT * DESIGN_ASPECT)
	_camera.fov = rad_to_deg(2.0 * atan(tan(_diagonal_fov / 2.0) / diagonal))


func _turn_character() -> void:
	if _character == null or not is_node_ready():
		return
	var toward_camera: Vector3 = _camera.position - _stand
	_character.position = _stand
	_character.rotation.y = atan2(-toward_camera.x, -toward_camera.z) + deg_to_rad(facing)


func _apply_glow() -> void:
	if not is_node_ready():
		return
	_environment.glow_enabled = glow > 0.0
	_environment.glow_intensity = glow


func _apply_fog() -> void:
	if not is_node_ready():
		return
	_environment.fog_enabled = fog_far > 0.0
	_environment.fog_light_color = fog_color
	_environment.fog_depth_begin = fog_near
	_environment.fog_depth_end = fog_far
