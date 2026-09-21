class_name WmoLiquidCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 15000
# The Trade District, from where Stormwind's own canals stream in with the city.
const STORMWIND: Vector3 = Vector3(-8913.0, 554.0, 94.0)
const HOME: Vector3 = Vector3(-6248.77, 317.339, 382.778)
# How far under the surface to aim, so the player is in the water rather than on its skin.
const DIVE: float = 2.0

var _failures: PackedStringArray = []
var _main: Main
var _sent: PackedStringArray = []


# A WMO's own water: Stormwind's canals answer liquid_height_at, and the player swims in them.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = "127.0.0.1"
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
	var player: Player = _main.world.player()
	player.movement_changed.connect(
		func(opcode: String, _at: Vector3, _facing: float, _flags: int, _fall: int,
				_jump: Vector3, _counter: int, _tail: PackedByteArray) -> void:
			_sent.append(opcode)
	)
	var map: WowMap = _main.world.get_node("WowMap")
	await _teleport(STORMWIND)
	var liquids: Array[Dictionary] = []
	for attempt: int in 8:
		liquids = map._wmo_liquids
		if not liquids.is_empty():
			break
		await _frames(120)
	print("WMO liquid surfaces around Stormwind: ", liquids.size())
	_check(not liquids.is_empty(), "Stormwind's WMO brings its own water")
	if liquids.is_empty():
		await _teleport(HOME)
		return _finish("no WMO liquid to swim in")

	var widest: Dictionary = liquids[0]
	for liquid: Dictionary in liquids:
		if (liquid["box"] as AABB).get_volume() > (widest["box"] as AABB).get_volume():
			widest = liquid
	var box: AABB = widest["box"]
	var spot: Vector3 = Vector3(box.get_center().x, widest["top"] - DIVE, box.get_center().z)
	print("swimming at %v, surface %.1f" % [spot, widest["top"]])
	_check(not is_nan(map.liquid_height_at(spot)), "and answers what its surface stands at")
	_check(
		is_nan(map.liquid_height_at(spot + Vector3(0.0, box.size.y + DIVE * 2.0, 0.0))),
		"only inside the water, not above it",
	)

	_sent.clear()
	await _teleport(WowCoords.from_godot(spot))
	var swimming: bool = await _until(func() -> bool: return "MSG_MOVE_START_SWIM" in _sent)
	_check(swimming, "and the player swims once dropped into it")
	await _teleport(HOME)
	_finish("")


func _teleport(wow_position: Vector3) -> void:
	WowClient.session.send_chat(
		WowSession.CHAT_SAY, ".go xyz %f %f %f" % [wow_position.x, wow_position.y, wow_position.z]
	)
	await _frames(30)
	await _until(func() -> bool: return _main.world.player().active, TIMEOUT_MSEC)
	await _frames(120)


func _until(condition: Callable, timeout_msec: int = STEP_MSEC) -> bool:
	var until: int = Time.get_ticks_msec() + timeout_msec
	while not condition.call() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	return condition.call()


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)


func _finish(fatal: String) -> void:
	if not fatal.is_empty():
		_failures.append(fatal)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("wmo_liquid_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
