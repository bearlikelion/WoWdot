class_name TestModels
extends Node

const TIMBER_WOLF: int = 165
const GOLDSHIRE_INN: String = "World\\wmo\\Azeroth\\Buildings\\GoldshireInn\\GoldshireInn.wmo"

var _failures: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var wolf: WowModel = WowModel.new()
	wolf.display_id = TIMBER_WOLF
	add_child(wolf)
	var inn: WowModel = WowModel.new()
	inn.model_path = GOLDSHIRE_INN
	add_child(inn)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(wolf.model != null, "wolf builds from its display id")
	if wolf.model:
		var player: AnimationPlayer = wolf.model.get_node_or_null("AnimationPlayer")
		_check(player != null and player.current_animation == "Stand", "wolf plays Stand")
		_check(wolf.model.get_node_or_null("Skeleton") is Skeleton3D, "wolf has a skeleton")
		_check(wolf.model.owner == null, "generated nodes are never saved")
	_check(inn.model != null, "inn builds from its WMO path")
	if inn.model:
		var shapes: Array[Node] = inn.model.find_children("*", "CollisionShape3D", true, false)
		_check(not shapes.is_empty(), "inn groups have collision")
		_check(inn.model.get_node_or_null("Doodads") != null, "inn places its doodads")

	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("test_models: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)
