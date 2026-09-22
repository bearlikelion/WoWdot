class_name BlobShadow
extends Decal

# The stock box is clamped into five yards each way.
const MAX_EXTENT: float = 10.0
const DEPTH: float = 3.0

static var _blob: ImageTexture


# The stock blob multiplies the ground darker; a decal mixes, so its grey becomes black at that alpha.
func _ready() -> void:
	if _blob == null:
		var image: Image = texture_albedo.get_image().duplicate()
		image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		image.clear_mipmaps()
		var data: PackedByteArray = image.get_data()
		for i: int in range(0, data.size(), 4):
			data[i + 3] = floori((255 - data[i]) * data[i + 3] / 255.0)
			data[i] = 0
			data[i + 1] = 0
			data[i + 2] = 0
		_blob = ImageTexture.create_from_image(Image.create_from_data(
			image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data
		))
	texture_albedo = _blob


func fit(bounds: AABB) -> void:
	size = Vector3(minf(bounds.size.x, MAX_EXTENT), DEPTH, minf(bounds.size.z, MAX_EXTENT))
	position = Vector3(bounds.get_center().x, 0.0, bounds.get_center().z)
