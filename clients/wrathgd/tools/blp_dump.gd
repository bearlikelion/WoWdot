class_name BlpDump
extends SceneTree

# Reports a texture's size, format and alpha spread, to tell a cutout from a solid card:
# godot --headless --path . --script tools/blp_dump.gd -- "Interface\...\Foo.blp"


func _initialize() -> void:
	for path: String in OS.get_cmdline_user_args():
		_dump(path)
	quit()


func _dump(path: String) -> void:
	var image: Image = WowLoader.get_shared().load_image(path)
	if image == null:
		print("%s: nothing read" % path)
		return
	var low: float = 1.0
	var high: float = 0.0
	var total: float = 0.0
	var rgb: Vector3 = Vector3.ZERO
	var step: int = maxi(1, image.get_width() / 64)
	var samples: int = 0
	for y: int in range(0, image.get_height(), step):
		for x: int in range(0, image.get_width(), step):
			var colour: Color = image.get_pixel(x, y)
			rgb += Vector3(colour.r, colour.g, colour.b)
			var a: float = colour.a
			low = minf(low, a)
			high = maxf(high, a)
			total += a
			samples += 1
	print("%s: %dx%d format %d alpha min %.2f max %.2f mean %.2f rgb %v" % [
		path.get_file(), image.get_width(), image.get_height(), image.get_format(),
		low, high, total / maxi(samples, 1), rgb / maxi(samples, 1),
	])
