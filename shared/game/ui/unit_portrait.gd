class_name UnitPortrait
extends SubViewport

# Frames to let the model settle before the single render the portrait keeps.
const SETTLE_FRAMES: int = 3
const FALLBACK_FOV: float = 35.0
# Without a portrait camera, frame the top of the model from this far away per unit of height.
const FALLBACK_DISTANCE: float = 0.55
const FALLBACK_HEAD: float = 0.12

@onready var _camera: Camera3D = %Camera
@onready var _slot: Node3D = %ModelSlot


func show_unit(guid: int) -> void:
	for child: Node in _slot.get_children():
		child.queue_free()
	var session: WowSession = WowClient.session
	if guid == 0 or not session.has_object(guid):
		return
	var display: int = session.get_field(guid, "UNIT_FIELD_DISPLAYID")
	var look: Dictionary = {}
	if session.get_object_type(guid) == Entities.ObjectType.PLAYER:
		look = CharacterModels.player_look(session, guid)
	var model: Node3D = WowAssets.creatures.instantiate(display, look)
	if model == null:
		return
	# The portrait camera frames the bind pose; the Stand slouch would drop the head out of shot.
	_slot.add_child(model)
	_aim(model, WowAssets.creatures.model_path(display))
	_render()


# The M2's first camera is the portrait camera SetPortraitTexture uses.
func _aim(model: Node3D, model_path: String) -> void:
	var cameras: Array = WowAssets.loader.get_m2_info(model_path).get("cameras", [])
	if not cameras.is_empty():
		var portrait: Dictionary = cameras[0]
		var eye: Vector3 = model.transform * (portrait["position"] as Vector3)
		var target: Vector3 = model.transform * (portrait["target"] as Vector3)
		_camera.fov = rad_to_deg(portrait["fov"])
		_camera.look_at_from_position(eye, target)
		return
	var bounds: AABB = AABB()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = model.transform * mesh.get_aabb()
		bounds = bounds.merge(box) if bounds.has_volume() else box
	var head: Vector3 = bounds.get_center()
	head.y = bounds.end.y - bounds.size.y * FALLBACK_HEAD
	_camera.fov = FALLBACK_FOV
	_camera.look_at_from_position(head + Vector3(0.0, 0.0, -bounds.size.y * FALLBACK_DISTANCE), head)


func _render() -> void:
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	render_target_update_mode = SubViewport.UPDATE_ONCE
