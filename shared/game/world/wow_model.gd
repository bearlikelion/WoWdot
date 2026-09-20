@tool
class_name WowModel
extends Node3D

@export var model_path: String = "":
	set(value):
		model_path = value
		_rebuild.call_deferred()
@export var display_id: int = 0:
	set(value):
		display_id = value
		_rebuild.call_deferred()
@export var animation: String = "Stand":
	set(value):
		animation = value
		_play()

var model: Node3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if model:
		model.queue_free()
		model = null
	if display_id > 0:
		model = WowAssets.creatures.instantiate(display_id)
	elif model_path.to_lower().ends_with(".wmo"):
		model = WowAssets.loader.load_wmo(model_path)
	elif not model_path.is_empty():
		model = WowAssets.loader.load_m2(model_path)
	if model == null:
		return
	# Left without an owner so the generated geometry is never saved into the scene.
	add_child(model)
	_play()


func _play() -> void:
	if model == null:
		return
	var player: AnimationPlayer = model.get_node_or_null("AnimationPlayer")
	if player and player.has_animation(animation):
		player.play(animation)
