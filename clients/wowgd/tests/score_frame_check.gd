class_name ScoreFrameCheck
extends Control

const WARSONG_GULCH: int = 489
const PLAYERS: int = 3

var _failures: PackedStringArray = []


func _ready() -> void:
	WowFonts.apply()
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://ui/world_state_score_frame.tscn")
	var frame: WorldStateScoreFrame = scene.instantiate()
	add_child(frame)
	frame.show_map(WARSONG_GULCH)
	frame.show()
	var scores: PackedByteArray = []
	scores.resize(5 + PLAYERS * 40)
	scores.encode_u32(1, PLAYERS)
	for i: int in PLAYERS:
		var at: int = 5 + i * 40
		scores.encode_u64(at, 100 + i)
		scores.encode_u32(at + 8, 5 + i)
		scores.encode_u32(at + 12, 7 * (i + 1))
		scores.encode_u32(at + 20, i)
		scores.encode_u32(at + 28, 2)
		scores.encode_u32(at + 32, i)
		scores.encode_u32(at + 36, 1)
	WowClient.session.packet_received.emit("MSG_PVP_LOG_DATA", scores)
	for i: int in 5:
		await get_tree().process_frame
	_check((frame.get_node("%WorldStateScoreButton3") as Control).visible, "three rows show")
	_check(not (frame.get_node("%WorldStateScoreButton4") as Control).visible, "the fourth hides")
	var blows: Label = frame.get_node("%WorldStateScoreButton2KillingBlows")
	_check(blows.text == "14", "killing blows fill in")
	var header: Label = frame.get_node("%WorldStateScoreFrameDeathsText")
	_check(header.text == WowStrings.get_text("DEATHS"), "fixed headers are titled")
	_check((frame.get_node("%WorldStateScoreColumn2") as Control).visible, "Warsong has two columns")
	_check(not (frame.get_node("%WorldStateScoreColumn3") as Control).visible, "and no third")
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png("user://score_frame_check.png")
	if _failures.is_empty():
		print("score_frame_check: OK")
	else:
		for line: String in _failures:
			print("  ", line)
		print("score_frame_check: FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)
