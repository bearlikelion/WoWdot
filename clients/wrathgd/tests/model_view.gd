class_name ModelView
extends Node3D

# Shows one model, or a slice of its surfaces, at a chosen point in its animation:
# godot --path . tests/model_view.tscn -- --m2=<path> --surfaces=0-14 --time=20 --out=<png>
const SETTLE_FRAMES: int = 30

@onready var _stage: Node3D = %Stage
@onready var _camera: Camera3D = %Camera


func _ready() -> void:
	var args: Dictionary[String, String] = _parse_args()
	var loader: WowLoader = WowLoader.get_shared()
	var model: Node3D = loader.load_m2(args.get("m2", ""))
	if model == null:
		printerr("model failed to load")
		get_tree().quit(1)
		return
	_stage.add_child(model)
	var kept: PackedInt32Array = _surface_range(args.get("surfaces", ""))
	if not kept.is_empty():
		_keep_surfaces(model, kept)
	var time: float = float(args.get("time", "0"))
	for player: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
		if player.has_animation(player.autoplay):
			player.play(player.autoplay)
			player.seek(time, true)
	_report(model, kept, time)
	if args.has("paint"):
		_paint(model, args["paint"] != "flat")
	if args.get("camera", "") == "model":
		_frame_model(loader, args.get("m2", ""))
	else:
		_frame(_bounds(model, kept), float(args.get("zoom", "1.0")))
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	var out: String = args.get("out", "user://model_view.png")
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(out)
	print("wrote ", ProjectSettings.globalize_path(out))
	get_tree().quit()


func _parse_args() -> Dictionary[String, String]:
	var args: Dictionary[String, String] = {}
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	return args


func _surface_range(text: String) -> PackedInt32Array:
	var kept: PackedInt32Array = []
	if text.is_empty():
		return kept
	for part: String in text.split(",", false):
		var ends: PackedStringArray = part.split("-", true, 1)
		var last: int = int(ends[1]) if ends.size() > 1 else int(ends[0])
		for surface: int in range(int(ends[0]), last + 1):
			kept.append(surface)
	return kept


func _keep_surfaces(model: Node3D, kept: PackedInt32Array) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for surface: int in mesh.mesh.get_surface_count():
			if kept.has(surface):
				continue
			var blank: StandardMaterial3D = StandardMaterial3D.new()
			blank.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			blank.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
			mesh.set_surface_override_material(surface, blank)


# Where the kept surfaces land once the pose is applied, which is not where they rest.
func _bounds(model: Node3D, kept: PackedInt32Array) -> AABB:
	var skeleton: Skeleton3D = model.find_child("Skeleton", true, false) as Skeleton3D
	var mesh: MeshInstance3D = model.find_child("Mesh", true, false) as MeshInstance3D
	if skeleton == null or mesh == null or mesh.mesh == null or kept.is_empty():
		var box: AABB = AABB()
		for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			box = box.merge(node.global_transform * node.get_aabb()) if box.has_volume() \
					else node.global_transform * node.get_aabb()
		return box
	var bounds: AABB = AABB()
	var started: bool = false
	for surface: int in kept:
		if surface >= mesh.mesh.get_surface_count():
			continue
		for point: Vector3 in _skinned(skeleton, mesh, surface):
			bounds = bounds.expand(point) if started else AABB(point, Vector3.ZERO)
			started = true
	return bounds


func _skinned(skeleton: Skeleton3D, mesh: MeshInstance3D, surface: int) -> PackedVector3Array:
	var skins: Array[Transform3D] = []
	for bone: int in skeleton.get_bone_count():
		skins.append(
			skeleton.get_bone_global_pose(bone) * skeleton.get_bone_global_rest(bone).affine_inverse()
		)
	var arrays: Array = mesh.mesh.surface_get_arrays(surface)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var posed: PackedVector3Array = []
	for v: int in points.size():
		var sum: Vector3 = Vector3.ZERO
		for k: int in 4:
			var weight: float = weights[v * 4 + k]
			if weight > 0.0:
				sum += skins[bones[v * 4 + k]] * points[v] * weight
		posed.append(sum)
	return posed


func _report(model: Node3D, kept: PackedInt32Array, time: float) -> void:
	var mesh: MeshInstance3D = model.find_child("Mesh", true, false) as MeshInstance3D
	var skeleton: Skeleton3D = model.find_child("Skeleton", true, false) as Skeleton3D
	if mesh == null or mesh.mesh == null:
		return
	print("surfaces %d, bones %d, showing %s at %.1fs" % [
		mesh.mesh.get_surface_count(), skeleton.get_bone_count() if skeleton else 0, kept, time,
	])


func _frame(bounds: AABB, zoom: float) -> void:
	var center: Vector3 = bounds.get_center()
	var distance: float = maxf(bounds.size.length(), 1.0) * 0.9 / zoom
	_camera.position = center + Vector3(0.7, 0.45, -1.0).normalized() * distance
	_camera.far = distance * 20.0
	_camera.look_at(center)
	print("framed %v size %v from %v" % [center, bounds.size, _camera.position])


# The same treatment the glue frames give a scene: flat shading in authored batch order.
func _paint(model: Node3D, order: bool) -> void:
	var priority: int = 0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for surface: int in mesh.mesh.get_surface_count():
			var material: BaseMaterial3D = mesh.get_surface_override_material(surface)
			if material == null:
				material = mesh.mesh.surface_get_material(surface)
				if material == null:
					continue
				material = material.duplicate()
				mesh.set_surface_override_material(surface, material)
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if not order or material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
				continue
			material.render_priority = mini(priority, 127)
			priority += 1


# The model's own camera, framed the way the client does: vfov = dfov / sqrt(1 + aspect squared).
func _frame_model(loader: WowLoader, path: String) -> void:
	var cameras: Array = loader.get_m2_info(path).get("cameras", [])
	if cameras.is_empty():
		return
	var view: Dictionary = cameras[0]
	var aspect: float = float(get_viewport().size.x) / get_viewport().size.y
	_camera.fov = rad_to_deg(float(view["fov"]) / sqrt(1.0 + aspect * aspect))
	_camera.far = 2000.0
	_camera.look_at_from_position(view["position"], view["target"])
	print("model camera fov %.1f at %v" % [_camera.fov, view["position"]])
