class_name LoadTiming
extends Node

# Logs in, enters the world and quits, printing when each stage came; run under tracy-capture.
const MAIN: PackedScene = preload("res://game/main.tscn")
const LINGER_MSEC: int = 3000

var _main: Main


func _ready() -> void:
	_mark("main scene ready")
	_main = MAIN.instantiate()
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	WowClient.session.state_changed.connect(
		func(state: WowSession.State, _message: String) -> void: _mark("session state %d" % state)
	)
	_main.world_ready.connect(_on_world_ready, CONNECT_ONE_SHOT)
	await get_tree().process_frame
	_mark("first frame")


func _on_world_ready(_world: World) -> void:
	_mark("world ready, loading screen gone")
	var quit_at: int = Time.get_ticks_msec() + LINGER_MSEC
	while Time.get_ticks_msec() < quit_at:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://load_timing.png")
	_mark("quitting")
	get_tree().quit()


func _mark(what: String) -> void:
	print("load_timing %7d ms  %s" % [Time.get_ticks_msec(), what])
