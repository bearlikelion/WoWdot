class_name TargetingCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000

var _failures: PackedStringArray = []
var _main: Main


# Presses the stock targeting keys in the world: Tab, Shift+Tab, F1, G and Escape.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var give_up: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _main.world == null or not _main.world.player().active:
		if Time.get_ticks_msec() > give_up:
			return _finish("never reached the world")
		await get_tree().process_frame
	await _frames(60)
	var hud: Hud = _main.world.hud()
	var session: WowSession = WowClient.session
	var me: int = session.get_player_guid()
	var player: Player = _main.world.player()
	var nearest: Vector3 = Vector3.INF
	for guid: int in session.get_object_guids():
		if session.get_object_type(guid) != Entities.ObjectType.UNIT \
		or UnitReaction.between(session, me, guid) == UnitReaction.Reaction.FRIENDLY \
		or session.get_field(guid, "UNIT_FIELD_HEALTH") == 0:
			continue
		var at: Vector3 = WowCoords.to_godot(session.get_object_position(guid))
		var here: Vector3 = player.global_position
		if at.distance_to(here) < minf(30.0, nearest.distance_to(here)):
			nearest = at
	if nearest == Vector3.INF:
		print("no enemy within 30 yards; Tab has nothing to find here")
		return _finish("")
	var toward: Vector3 = nearest - player.global_position
	player.rotation.y = atan2(-toward.x, -toward.z)
	await _frames(20)
	var entities: Entities = _main.world.get_node("Entities")
	var camera: Camera3D = get_viewport().get_camera_3d()
	var nearby: Array[int] = entities.visible_units(player.global_position, 40.0, camera)
	var enemies: int = 0
	for guid: int in nearby:
		if UnitReaction.between(session, me, guid) != UnitReaction.Reaction.FRIENDLY:
			enemies += 1
	await _press(KEY_TAB)
	var first: int = hud.target()
	_check(first != 0 and first != me, "Tab targets a unit")
	_check(
		UnitReaction.between(session, me, first) != UnitReaction.Reaction.FRIENDLY,
		"Tab picks an enemy",
	)
	await _press(KEY_TAB)
	var second: int = hud.target()
	print("%d enemies on screen, Tab picked %d then %d" % [enemies, first, second])
	_check((second != first) == (enemies > 1), "a second Tab moves on when there is another enemy")
	await _press(KEY_TAB, true)
	_check(hud.target() == first, "Shift+Tab goes back")
	await _press(KEY_F1)
	_check(hud.target() == me, "F1 targets yourself")
	await _press(KEY_G)
	_check(hud.target() == first, "G returns to the last hostile target")
	await _press(KEY_ESCAPE)
	_check(hud.target() == 0, "Escape clears the target")
	_finish("")


func _press(key: Key, shift: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.shift_pressed = shift
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(3)


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
	print("targeting_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
