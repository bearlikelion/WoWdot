class_name LoginCinematicCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000

var _failures: PackedStringArray = []
var _main: Main
var _triggered: bool = false
var _world_existed: bool = false


# A first login's intro, which the server sends in the same burst as the world itself.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	WowClient.session.packet_received.connect(_on_packet_received)
	_run.call_deferred()


func _run() -> void:
	var ready_at: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _main.world == null or not _main.world.player().active:
		if Time.get_ticks_msec() > ready_at:
			return _finish("never reached the world")
		await get_tree().process_frame
	var camera: CinematicCamera = _main.world.get_node("CinematicCamera")
	var flying_by: int = Time.get_ticks_msec() + 5000
	while not camera.current and Time.get_ticks_msec() < flying_by:
		await get_tree().process_frame
	_check(_triggered, "the server sent the intro")
	_check(_world_existed, "the world scene existed when it arrived")
	_check(camera.current, "the intro takes the camera")
	_check(not _main.find_child("Glue").visible, "the loading screen makes way for it")
	camera.stop()
	_finish("")


func _on_packet_received(opcode: String, _payload: PackedByteArray) -> void:
	if opcode == "SMSG_TRIGGER_CINEMATIC":
		_triggered = true
		_world_existed = _main.world != null


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)


func _finish(fatal: String) -> void:
	if not fatal.is_empty():
		_failures.append(fatal)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("login_cinematic_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
