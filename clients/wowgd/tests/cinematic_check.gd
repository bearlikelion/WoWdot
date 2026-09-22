class_name CinematicCheck
extends Node3D

# The human intro; every sequence in CinematicSequences.dbc names one camera model.
const HUMAN_INTRO: int = 81

var _failures: PackedStringArray = []
var _finished: bool = false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var camera: CinematicCamera = CinematicCamera.new()
	add_child(camera)
	camera.finished.connect(func() -> void: _finished = true)
	_check(camera.play(HUMAN_INTRO), "the human intro has a readable camera")
	for sequence: int in CinematicCamera.NARRATION:
		_check(
			WowAssets.audio.entry_stream(CinematicCamera.NARRATION[sequence]) != null,
			"sequence %d has a readable narration" % sequence
		)
	var start: Vector3 = camera.global_position
	for i: int in 30:
		await get_tree().process_frame
	_check(not camera.global_position.is_equal_approx(start), "the camera moves along its track")
	_check(not _finished, "and is still flying half a second in")
	camera.stop()
	_check(_finished, "stopping finishes the sequence")
	_check(not camera.play(999999), "an unknown sequence is refused")
	if _failures.is_empty():
		print("cinematic_check: OK")
	else:
		for line: String in _failures:
			print("  ", line)
		print("cinematic_check: FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)
