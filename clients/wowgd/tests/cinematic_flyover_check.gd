class_name CinematicFlyoverCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const HUMAN_INTRO: int = 81

var _failures: PackedStringArray = []
var _main: Main


# Has the server play the human intro over Northshire, as a new character's first login would.
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
	var world: World = _main.world
	var camera: CinematicCamera = world.get_node("CinematicCamera")
	var hud: Control = world.get_node("%Hud")
	WowClient.session.send_chat(WowSession.CHAT_SAY, ".debug play cinematic %d" % HUMAN_INTRO)
	var flying_by: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while not camera.current and Time.get_ticks_msec() < flying_by:
		await get_tree().process_frame
	_check(camera.current, "the server's cinematic takes the camera")
	_check(not hud.visible, "the interface hides for it")
	await get_tree().create_timer(4.0).timeout
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png("user://cinematic_flyover_check.png")
	camera.stop()
	await get_tree().process_frame
	_check(hud.visible, "the interface returns after it")
	_check(not camera.current, "and so does the player's camera")
	_finish("")


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)


func _finish(fatal: String) -> void:
	if not fatal.is_empty():
		_failures.append(fatal)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("cinematic_flyover_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
