class_name ClutterCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000

var _failures: PackedStringArray = []
var _main: Main


# Coldridge Valley's snow carries ground effects, so clutter scatters round the player.
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
	Input.action_press("move_forward")
	await get_tree().create_timer(4.0).timeout
	Input.action_release("move_forward")
	# Turn round and look down at the trail just walked.
	var player: Player = _main.world.player()
	player.rotation.y += PI
	(player.get_node("CameraPivot") as Node3D).rotation.x = -1.2
	(player.get_node("CameraPivot/SpringArm3D") as SpringArm3D).spring_length = 2.0
	await get_tree().create_timer(1.0).timeout
	var prints: Footprints = _main.world.get_node("Footprints")
	var stamped: int = prints.get_children().filter(
		func(d: Node) -> bool: return (d as Decal).visible
	).size()
	print("  footprints ", stamped)
	_check(stamped > 0, "walking leaves footprints")
	var clutter: GroundClutter = _main.world.get_node("GroundClutter")
	var instances: int = 0
	for holder: Node in clutter.get_children():
		for multi: MultiMeshInstance3D in holder.get_children():
			instances += multi.multimesh.instance_count
	print("  clutter chunks ", clutter.get_child_count(), " doodads ", instances)
	_check(clutter.get_child_count() > 0, "chunks in reach were scattered")
	_check(instances > 0, "and placed detail doodads")
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png("user://clutter_check.png")
	_finish("")


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)


func _finish(fatal: String) -> void:
	if not fatal.is_empty():
		_failures.append(fatal)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("clutter_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
