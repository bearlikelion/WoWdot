class_name HorizonCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000

var _failures: PackedStringArray = []
var _main: Main


func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var ready_at: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _main.world == null or not _main.world.player().active:
		if Time.get_ticks_msec() > ready_at:
			return _finish("never reached the world")
		await get_tree().process_frame
	# The Thelsamar road over Loch Modan looks east across the whole loch.
	WowClient.session.send_chat(WowSession.CHAT_SAY, ".go xyz -5150 -3300 320 0")
	await get_tree().create_timer(15.0).timeout
	var horizon: WorldHorizon = _main.world.get_node("WorldHorizon")
	var loaded: int = _main.world.get_node("WowMap").loaded_tiles().size()
	var faces: int = horizon.mesh.get_faces().size() / 3 if horizon.mesh else 0
	print("  loaded tiles ", loaded, " horizon faces ", faces)
	_check(faces > 0, "the horizon mesh covers the map")
	_check(faces < 4096 * 512, "with the loaded tiles cut out")
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png("user://horizon_check.png")
	_finish("")


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)


func _finish(fatal: String) -> void:
	if not fatal.is_empty():
		_failures.append(fatal)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("horizon_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
