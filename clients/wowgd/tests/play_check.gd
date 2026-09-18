class_name PlayCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const RUN_SECONDS: float = 2.0
const MAX_SAVED_ERROR: float = 1.5
const TIMEOUT_MSEC: int = 60000
# The Northshire start; each run heads back toward it so repeated checks stay nearby.
const HOME: Vector3 = Vector3(-8949.95, -132.49, 83.53)
const SAY_TEXT: String = "play_check says hello"
# Take-off speed squared over twice the gravity: 7.958 * 7.958 / (2 * 19.29).
const JUMP_HEIGHT: float = 1.64

var _failures: PackedStringArray = []
var _main: Main
var _characters: Array = []
var _sent: PackedStringArray = []


# Plays the real game flow in a window: login, walk with the input actions, then check the server.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	_main.auto_character = "Tessaline"
	add_child(_main)
	WowClient.session.characters_received.connect(_on_characters_received)
	_run.call_deferred()


func _run() -> void:
	var tree: SceneTree = get_tree()
	var ready_at: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _main.world == null or not _main.world.player().active:
		var failed: bool = WowClient.session.get_state() == WowSession.STATE_FAILED
		if failed or Time.get_ticks_msec() > ready_at:
			return _finish("never reached the world")
		await tree.process_frame
	var world_map: WowMap = _main.world.get_node("WowMap")
	while not world_map.is_idle():
		await tree.process_frame
	await _frames(30)
	_capture("user://play_start.png")
	var camera: Camera3D = get_viewport().get_camera_3d()
	var above: float = camera.global_position.y - _main.world.player().global_position.y
	print("camera %.1f yd above the player, pitch %.2f rad" % [above, camera.global_rotation.x])
	var entities: int = _main.world.get_node("Entities").get_child_count()
	print("entity models in the world: %d" % entities)
	_check(entities > 10, "creatures and objects spawn as models")
	await _check_hud()

	var player: Player = _main.world.player()
	player.movement_changed.connect(_on_movement_changed)
	var start: Vector3 = player.global_position
	var toward_home: Vector3 = HOME - WowCoords.from_godot(start)
	player.rotation.y = atan2(toward_home.y, toward_home.x) if toward_home.length() > 5.0 else 0.0
	Input.action_press("move_forward")
	await tree.create_timer(RUN_SECONDS).timeout
	Input.action_release("move_forward")
	await _frames(20)
	var ran: float = start.distance_to(player.global_position)
	print("ran %.1f yd to %s" % [ran, WowCoords.from_godot(player.global_position)])
	print("sent while running: ", _sent)
	_check(not _sent.has("MSG_MOVE_FALL_LAND"), "running over the ground never counts as a fall")
	_check(ran > 10.0, "the player moved with the move_forward action")
	_capture("user://play_after_run.png")
	await _check_jump(player)

	var expected: Vector3 = WowCoords.from_godot(player.global_position)
	_characters.clear()
	WowClient.session.logout()
	var logout_at: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _characters.is_empty() and Time.get_ticks_msec() < logout_at:
		await tree.process_frame
	for saved: Dictionary in _characters:
		if saved["name"] == "Tessaline":
			var off: float = (saved["position"] as Vector3).distance_to(expected)
			print("server saved %s, client at %s" % [saved["position"], expected])
			_check(off < MAX_SAVED_ERROR, "server position matches the client (%.2f yd off)" % off)
	_finish("")


func _check_jump(player: Player) -> void:
	var ground: float = player.global_position.y
	var peak: float = ground
	var left_ground: bool = false
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	var land_by: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < land_by:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
		left_ground = left_ground or not player.is_on_floor()
		if left_ground and player.is_on_floor():
			break
	print("jumped %.2f yd" % (peak - ground))
	_check(absf(peak - ground - JUMP_HEIGHT) < 0.2, "the jump reaches the stock height")
	_check(left_ground and player.is_on_floor(), "the jump lands")
	await _frames(10)


func _check_hud() -> void:
	var hud: Hud = _main.world.hud()
	var camera: Camera3D = get_viewport().get_camera_3d()
	var player: Vector3 = _main.world.player().global_position
	var named: int = 0
	var aim: Vector3 = Vector3.INF
	for node: Node in _main.world.get_node("Entities").find_children("*", "Label3D", true, false):
		var plate: Label3D = node
		if plate.text.is_empty():
			continue
		named += 1
		var body: Vector3 = plate.get_parent_node_3d().global_position.lerp(plate.global_position, 0.4)
		var visible: bool = not camera.is_position_behind(body) \
		and get_viewport().get_visible_rect().has_point(camera.unproject_position(body))
		if visible and body.distance_to(player) < aim.distance_to(player):
			aim = body
	print("entities with names: %d" % named)
	_check(named > 10, "nameplates show names")
	_check(hud.get_node("%PlayerFrame").visible, "the player frame shows")
	if aim != Vector3.INF:
		# Emitted directly: a moving desktop cursor would turn injected clicks into drags.
		_main.world.player().clicked.emit(camera.unproject_position(aim))
		await _frames(2)
		print("clicked target: ", WowClient.session.get_object_name(hud.target()))
	_check(hud.target() != 0, "clicking a creature targets it")

	var chat: InputEventAction = InputEventAction.new()
	chat.action = "chat"
	chat.pressed = true
	Input.parse_input_event(chat)
	await _frames(2)
	var chat_input: LineEdit = hud.get_node("%ChatInput")
	_check(chat_input.has_focus(), "the chat action opens the chat box")
	chat_input.text = "/s " + SAY_TEXT
	chat_input.text_submitted.emit(chat_input.text)
	var chat_log: RichTextLabel = hud.get_node("%ChatLog")
	var said: String = "Tessaline says: " + SAY_TEXT
	var heard_at: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while not chat_log.get_parsed_text().contains(said) and Time.get_ticks_msec() < heard_at:
		await get_tree().process_frame
	_check(chat_log.get_parsed_text().contains(said), "a say typed in the chat box comes back")
	await _frames(5)
	_capture("user://play_hud.png")


func _on_movement_changed(
	opcode: String, _position: Vector3, _orientation: float, _flags: int,
	_fall_time_msec: int, _jump_velocity: Vector3,
) -> void:
	_sent.append(opcode)


func _on_characters_received(characters: Array) -> void:
	_characters = characters.duplicate()


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _capture(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)


func _finish(fatal: String) -> void:
	if not fatal.is_empty():
		_failures.append(fatal)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("play_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
