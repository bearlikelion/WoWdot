class_name WowCursor
extends RefCounted

enum Kind { POINT, ATTACK, SPEAK, BUY, TAXI, TRAINER, PICKUP, INTERACT, MAIL, CAST }

const FILES: Dictionary[Kind, String] = {
	Kind.POINT: "Point",
	Kind.ATTACK: "Attack",
	Kind.SPEAK: "Speak",
	Kind.BUY: "Buy",
	Kind.TAXI: "Taxi",
	Kind.TRAINER: "Trainer",
	Kind.PICKUP: "Pickup",
	Kind.INTERACT: "Interact",
	Kind.MAIL: "Mail",
	Kind.CAST: "Cast",
}
const PATH: String = "Interface\\Cursor\\%s%s.blp"

static var _images: Dictionary[String, Image] = {}
static var _shown: String = ""


# Every stock cursor has an Unable twin, shown while the thing under it is out of reach.
static func show(kind: Kind, in_reach: bool = true) -> void:
	var path: String = PATH % ["" if in_reach or kind == Kind.POINT else "Unable", FILES[kind]]
	if path == _shown:
		return
	_shown = path
	if not _images.has(path):
		var image: Image = WowAssets.loader.load_image(path)
		if image:
			image.decompress()
			image.clear_mipmaps()
		_images[path] = image
	if _images[path]:
		Input.set_custom_mouse_cursor(_images[path])
