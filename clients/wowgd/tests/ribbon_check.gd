class_name RibbonCheck
extends Node3D

# A totem whose spinning bones carry two ribbons, which makes the trail obvious.
const MODEL: String = "Creature\\Spells\\AirElementalTotem.m2"
const SAMPLES: int = 200
const SETTLE_FRAMES: int = 120

var _failures: PackedStringArray = []


# M2 ribbon emitters: the vanilla layout parses, and the trail grows behind a moving bone.
func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var found: int = 0
	for path: String in WowAssets.archive.find("*.m2").slice(0, SAMPLES):
		found += int(not (WowAssets.loader.get_m2_info(path).get("ribbons", []) as Array).is_empty())
	print("models with ribbons in the first %d: %d" % [SAMPLES, found])
	var info: Dictionary = WowAssets.loader.get_m2_info(MODEL)
	var emitters: Array = info.get("ribbons", [])
	_check(not emitters.is_empty(), "a vanilla model reports its ribbon emitters")
	if emitters.is_empty():
		return _finish()
	var first: Dictionary = emitters[0]
	print("first emitter: ", first)
	_check(first["edges_per_second"] > 1.0, "with an edge rate the layout could only give if it fits")
	_check(first["lifetime"] > 0.05 and first["lifetime"] < 10.0, "and a lifetime in range")
	_check(not String(first["texture"]).is_empty(), "and a texture of its own")

	var model: Node3D = WowAssets.loader.load_m2(MODEL)
	_check(model != null, "the model loads")
	if model == null:
		return _finish()
	add_child(model)
	var trails: Array[Node] = model.find_children("Ribbon*", "WowRibbon", true, false)
	_check(trails.size() == emitters.size(), "each emitter builds a trail node")
	var player: AnimationPlayer = model.get_node_or_null("AnimationPlayer")
	if player and player.get_animation_list().size() > 0:
		player.play(player.get_animation_list()[0])
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	if not trails.is_empty():
		var trail: WowRibbon = trails[0]
		print("edges after %d frames: %d" % [SETTLE_FRAMES, trail.get_edge_count()])
		_check(trail.get_edge_count() > 1, "and the trail records edges as the bone moves")
		_check(
			trail.mesh != null and (trail.mesh as ImmediateMesh).get_surface_count() > 0,
			"which build into a strip",
		)
	_finish()


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)


func _finish() -> void:
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("ribbon_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
