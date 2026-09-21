class_name UiView
extends Control

# WoW lays its interface out on a 768 unit tall screen.
const UI_HEIGHT: float = 768.0
const SETTLE_FRAMES: int = 10

@onready var _root: Control = $Root


# Renders one converted FrameXML scene: -- --scene=res://... [--out=user://ui_view.png]
func _ready() -> void:
	var args: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	WowFonts.apply()
	var ui_scale: float = get_viewport_rect().size.y / UI_HEIGHT
	_root.scale = Vector2(ui_scale, ui_scale)
	_root.size = get_viewport_rect().size / ui_scale
	var scene: PackedScene = load(args.get("scene", "res://ui/main_menu_bar.tscn"))
	var view: Control = scene.instantiate()
	_root.add_child(view)
	view.show()
	# A frame the game sizes at runtime, such as a chat bubble, needs one given here.
	if args.has("size"):
		var wide: PackedStringArray = String(args["size"]).split("x")
		view.size = Vector2(float(wide[0]), float(wide[1]))
	var label: Label = view.get_node_or_null("%Text") as Label
	if label != null and args.has("text"):
		label.text = args["text"]
	for path: String in args.get("show", "").split(",", false):
		(view.get_node(NodePath(path)) as CanvasItem).show()
	for i: int in int(args.get("settle", str(SETTLE_FRAMES))):
		await get_tree().process_frame
	var out: String = args.get("out", "user://ui_view.png")
	# A locked screen never asks for a frame, so draw one rather than save the last one from before.
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(out)
	print("wrote ", ProjectSettings.globalize_path(out))
	get_tree().quit()
