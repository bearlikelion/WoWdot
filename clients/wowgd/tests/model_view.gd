class_name ModelView
extends Node3D

const SETTLE_FRAMES: int = 45

@onready var _stage: Node3D = $Stage
@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	var args: Dictionary = _parse_args()
	var archive: WowArchive = WowArchive.new()
	archive.open(ProjectSettings.get_setting("wowgd/client_data_dir"))
	var loader: WowLoader = WowLoader.new()
	loader.archive = archive

	var model: Node3D = null
	if args.has("wmo"):
		model = loader.load_wmo(args["wmo"])
	elif args.has("display"):
		var look: Dictionary = {}
		if args.has("look"):
			var values: PackedFloat64Array = String(args["look"]).split_floats(",")
			var keys: PackedStringArray = [
				"race", "gender", "skin", "face", "hair_style", "hair_color", "facial_hair",
			]
			for i: int in keys.size():
				look[keys[i]] = int(values[i])
		var characters: CharacterModels = CharacterModels.new(loader)
		model = CreatureModels.new(loader, characters).instantiate(int(args["display"]), look)
	else:
		var geosets: PackedInt32Array = []
		for value: float in String(args.get("geosets", "")).split_floats(",", false):
			geosets.append(int(value))
		var skins: Dictionary = {}
		if args.has("skin_png"):
			skins[1] = ImageTexture.create_from_image(Image.load_from_file(args["skin_png"]))
		model = loader.load_m2(args.get("m2", "Creature\\Wolf\\Wolf.m2"), skins, geosets)
	if model == null:
		printerr("model failed to load")
		get_tree().quit(1)
		return
	_stage.add_child(model)
	_play(model, args.get("anim", ""))
	var view: PackedFloat64Array = String(args.get("view", "0.7,0.45,-1")).split_floats(",")
	_frame(_bounds(model), float(args.get("zoom", "1.0")), Vector3(view[0], view[1], view[2]))

	for i: int in int(args.get("settle", str(SETTLE_FRAMES))):
		await get_tree().process_frame
	var out: String = args.get("out", "user://model_view.png")
	get_viewport().get_texture().get_image().save_png(out)
	print("wrote ", ProjectSettings.globalize_path(out))
	get_tree().quit()


func _parse_args() -> Dictionary:
	var args: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	return args


func _play(model: Node3D, anim: String) -> void:
	var player: AnimationPlayer = model.get_node_or_null("AnimationPlayer")
	if player == null:
		return
	print("animations: ", player.get_animation_list().size())
	var clip: String = anim if player.has_animation(anim) else "Stand"
	if player.has_animation(clip):
		player.play(clip)


func _bounds(root: Node3D) -> AABB:
	var bounds: AABB = AABB()
	var first: bool = true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


# The default view is the front (Godot -Z) quarter, since M2 models face WoW +X.
func _frame(bounds: AABB, zoom: float, view: Vector3) -> void:
	var center: Vector3 = bounds.get_center()
	var distance: float = max(bounds.size.length(), 1.0) * 0.9 / zoom
	_camera.position = center + view.normalized() * distance
	_camera.far = distance * 10.0
	_camera.look_at(center)
