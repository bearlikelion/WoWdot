class_name EffectsCheck
extends Node

# Water, fire and portals scroll their UVs and throw particles, so a sample should show both.
const SAMPLES: int = 40
const MASKS: PackedStringArray = [
	"*portal*.m2", "*lava*.m2", "*falls*.m2", "*fire*.m2", "*moonwell*.m2", "*water*.m2",
]

var _failures: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var animated: PackedStringArray = []
	var emitting: PackedStringArray = []
	var looked_at: int = 0
	for mask: String in MASKS:
		for path: String in WowAssets.archive.find(mask).slice(0, SAMPLES):
			var model: Node3D = WowAssets.loader.load_m2(path)
			if model == null:
				continue
			looked_at += 1
			var player: AnimationPlayer = model.get_node_or_null("TextureAnimation")
			if player and player.get_animation("Textures").get_track_count() > 0:
				animated.append("%s (%d tracks)" % [
					path.get_file(), player.get_animation("Textures").get_track_count(),
				])
			var emitters: int = model.find_children("Particles*", "GPUParticles3D", true, false).size()
			if emitters > 0:
				emitting.append("%s (%d emitters)" % [path.get_file(), emitters])
			model.queue_free()
	print("models read: %d, scrolling: %d, emitting: %d" % [
		looked_at, animated.size(), emitting.size(),
	])
	for name: String in animated.slice(0, 3):
		print("  scrolls ", name)
	for name: String in emitting.slice(0, 3):
		print("  emits ", name)
	_check(looked_at > 0, "the archive holds models to read")
	_check(not animated.is_empty(), "some of them scroll their textures")
	_check(not emitting.is_empty(), "some of them throw particles")
	_finish()


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)


func _finish() -> void:
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	var result: String = "OK" if _failures.is_empty() else "%d failed" % _failures.size()
	print("effects_check: ", result)
	get_tree().quit(0 if _failures.is_empty() else 1)
