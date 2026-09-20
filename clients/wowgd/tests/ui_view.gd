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
	var scene: PackedScene = load(args.get("scene", "res://game/ui/wow/main_menu_bar.tscn"))
	var view: Control = scene.instantiate()
	_root.add_child(view)
	view.show()
	for path: String in args.get("show", "").split(",", false):
		(view.get_node(NodePath(path)) as CanvasItem).show()
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	var out: String = args.get("out", "user://ui_view.png")
	get_viewport().get_texture().get_image().save_png(out)
	print("wrote ", ProjectSettings.globalize_path(out))
	get_tree().quit()
