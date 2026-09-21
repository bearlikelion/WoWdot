class_name RibbonTrail
extends MeshInstance3D

# The emitter's M2 values: how often an edge is laid down, how long it lives, and its half widths.
var edges_per_second: float = 30.0
var lifetime: float = 0.5
var above: float = 0.1
var below: float = 0.1
var gravity: float = 0.0

var _edges: Array[Edge] = []
var _since_edge: float = 0.0
var _strip: ImmediateMesh = ImmediateMesh.new()


# The strip is drawn in world space, so the bone it rides only says where the next edge goes.
func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _strip
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	var source: Node3D = get_parent()
	for edge: Edge in _edges:
		edge.age += delta
		edge.fall += gravity * delta * delta
	while not _edges.is_empty() and _edges[0].age > lifetime:
		_edges.pop_front()
	_since_edge += delta
	if _since_edge >= 1.0 / maxf(edges_per_second, 1.0):
		_since_edge = 0.0
		var edge: Edge = Edge.new()
		edge.center = source.global_position
		edge.up = source.global_basis.y.normalized()
		_edges.append(edge)
	_draw(source)


# The newest edge always sits on the emitter, so the ribbon never lags behind a fast missile.
func _draw(source: Node3D) -> void:
	_strip.clear_surfaces()
	if _edges.is_empty():
		return
	_strip.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var last: int = _edges.size()
	for i: int in last + 1:
		var center: Vector3 = source.global_position if i == last else _edges[i].center
		var up: Vector3 = source.global_basis.y.normalized() if i == last else _edges[i].up
		var age: float = 0.0 if i == last else _edges[i].age
		var fall: Vector3 = Vector3.ZERO if i == last else Vector3.DOWN * _edges[i].fall
		var along: float = clampf(age / lifetime, 0.0, 1.0)
		_strip.surface_set_color(Color(1.0, 1.0, 1.0, 1.0 - along))
		_strip.surface_set_uv(Vector2(along, 0.0))
		_strip.surface_add_vertex(center + fall + up * above)
		_strip.surface_set_color(Color(1.0, 1.0, 1.0, 1.0 - along))
		_strip.surface_set_uv(Vector2(along, 1.0))
		_strip.surface_add_vertex(center + fall - up * below)
	_strip.surface_end()


# Hangs a trail on every ribbon emitter the model's M2 declares.
static func attach(model: Node3D, m2_path: String) -> void:
	var ribbons: Array = WowAssets.loader.get_m2_info(m2_path).get("ribbons", [])
	if ribbons.is_empty():
		return
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false).pop_front()
	for ribbon: Dictionary in ribbons:
		if String(ribbon["texture"]).is_empty():
			continue
		var trail: RibbonTrail = RibbonTrail.new()
		trail.edges_per_second = ribbon["edges_per_second"]
		trail.lifetime = maxf(ribbon["lifetime"], 0.05)
		trail.above = ribbon["above"]
		trail.below = ribbon["below"]
		trail.gravity = ribbon["gravity"]
		trail.material_override = _material(ribbon["texture"])
		var mount: Node3D = model
		var offset: Vector3 = ribbon["position"]
		if skeleton and ribbon["bone"] >= 0 and ribbon["bone"] < skeleton.get_bone_count():
			var bone: BoneAttachment3D = BoneAttachment3D.new()
			bone.bone_idx = ribbon["bone"]
			skeleton.add_child(bone)
			mount = bone
			# An M2 emitter's position is model space, like the bone's pivot.
			offset -= skeleton.get_bone_global_rest(ribbon["bone"]).origin
		var anchor: Node3D = Node3D.new()
		anchor.position = offset
		mount.add_child(anchor)
		anchor.add_child(trail)


# ponytail: ribbons draw white and additive; their colour and blend tracks are not read yet.
static func _material(texture_path: String) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = WowAssets.loader.load_texture(texture_path)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.disable_fog = true
	return material


class Edge:
	var center: Vector3
	var up: Vector3
	var age: float = 0.0
	var fall: float = 0.0
