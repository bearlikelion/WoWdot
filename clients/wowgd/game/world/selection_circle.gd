class_name SelectionCircle
extends Decal

# The stock ring sits a little wider than the unit it marks.
const RADIUS_SCALE: float = 1.5
const MIN_RADIUS: float = 0.5

@export var entities: Entities

var target: int = 0


# Decal emission ignores the albedo alpha, so the glow copy keeps the ring's shape in its colour.
func _ready() -> void:
	var image: Image = texture_albedo.get_image().duplicate()
	image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = image.get_data()
	for i: int in range(0, data.size(), 4):
		data[i] = data[i + 3]
		data[i + 1] = data[i + 3]
		data[i + 2] = data[i + 3]
	var glow: Image = Image.create_from_data(
		image.get_width(), image.get_height(), image.has_mipmaps(), Image.FORMAT_RGBA8, data
	)
	texture_emission = ImageTexture.create_from_image(glow)


# Follows the target, tinted by its reaction, with the ring's bright rim toward the camera.
func _process(_delta: float) -> void:
	var node: Node3D = entities.unit_node(target) if target != 0 else null
	visible = node != null
	if node == null:
		return
	global_position = node.global_position
	var radius: float = maxf(entities.unit_radius(target), MIN_RADIUS) * RADIUS_SCALE
	size = Vector3(radius * 2.0, size.y, radius * 2.0)
	var session: WowSession = WowClient.session
	modulate = UnitReaction.COLORS[UnitReaction.between(session, session.get_player_guid(), target)]
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		var to_camera: Vector3 = camera.global_position - global_position
		rotation.y = atan2(to_camera.x, to_camera.z)
