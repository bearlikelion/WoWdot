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
	player.rotation.y = _clear_heading(player, atan2(toward_home.y, toward_home.x))
	Input.action_press("move_forward")
	await tree.create_timer(RUN_SECONDS).timeout
	Input.action_release("move_forward")
	await _frames(20)
	var ran: float = start.distance_to(player.global_position)
	print("ran %.1f yd to %s" % [ran, WowCoords.from_godot(player.global_position)])
	print("sent while running: ", _sent)
	_check(not _sent.has("MSG_MOVE_FALL_LAND"), "running over the ground never counts as a fall")
	# Doodads collide now, so a tree in the way can cut the run short.
	_check(ran > 4.0, "the player moved with the move_forward action")
	_capture("user://play_after_run.png")
	await _check_jump(player)

	var expected: Vector3 = WowCoords.from_godot(player.global_position)
	var player_name: String = WowClient.session.get_object_name(WowClient.session.get_player_guid())
	_characters.clear()
	WowClient.session.logout()
	var logout_at: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _characters.is_empty() and Time.get_ticks_msec() < logout_at:
		await tree.process_frame
	for saved: Dictionary in _characters:
		if saved["name"] == player_name:
			var off: float = (saved["position"] as Vector3).distance_to(expected)
			print("server saved %s, client at %s" % [saved["position"], expected])
			_check(off < MAX_SAVED_ERROR, "server position matches the client (%.2f yd off)" % off)
	_finish("")


# The heading nearest the wanted one whose first few yards are free of doodads and walls.
func _clear_heading(player: Player, wanted: float) -> float:
	const PROBE_YARDS: float = 4.0
	const CLIMB: float = 1.0
	for step: int in 8:
		var heading: float = wanted + PI / 4.0 * ((step + 1) >> 1) * (1 if step % 2 == 0 else -1)
		var forward: Vector3 = Basis(Vector3.UP, heading) * Vector3.FORWARD
		if not player.test_move(player.global_transform, forward * PROBE_YARDS + Vector3.UP * CLIMB):
			return heading
	return wanted


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
	var loaded: bool = hud != null and hud.get_node_or_null("%MainMenuBar") is MainMenuBar
	if not _check(loaded, "the HUD loads"):
		return
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
	var chat_frame: ChatFrame = hud.get_node("%ChatFrame1")
	var chat_input: LineEdit = chat_frame.get_node("%ChatFrameEditBox")
	_check(chat_input.has_focus(), "the chat action opens the chat box")
	for character: String in "/y typing":
		var key: InputEventKey = InputEventKey.new()
		key.unicode = character.unicode_at(0)
		key.keycode = OS.find_keycode_from_string(character) if character != " " else KEY_SPACE
		key.pressed = true
		Input.parse_input_event(key)
		await get_tree().process_frame
	await _frames(3)
	_capture("user://play_chat_edit.png")
	var header: Label = chat_frame.get_node("%ChatFrameEditBoxHeader")
	_check(header.text.begins_with("Yell"), "/y switches the header")
	chat_input.text = "/s " + SAY_TEXT
	chat_input.text_submitted.emit(chat_input.text)
	var session: WowSession = WowClient.session
	var speaker: String = session.get_object_name(session.get_player_guid())
	var said: String = "[%s] says: %s" % [speaker, SAY_TEXT]
	var heard_at: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while not chat_frame.all_text().contains(said) and Time.get_ticks_msec() < heard_at:
		await get_tree().process_frame
	_check(chat_frame.all_text().contains(said), "a say typed in the chat box comes back")
	await _check_casting_bar(hud)
	await _check_buffs(hud)
	await _check_errors(hud)
	await _check_multi_bars(hud)
	await _check_tooltips(hud)
	await _frames(5)
	_capture("user://play_hud.png")


# A warrior has no cast-time spells, so the bar is driven through the session's own signals.
func _check_casting_bar(hud: Hud) -> void:
	const FIREBALL: int = 133
	var session: WowSession = WowClient.session
	var bar: CastingBar = hud.get_node("%CastingBarFrame")
	session.spell_cast_started.emit(session.get_player_guid(), FIREBALL, 1500)
	await get_tree().create_timer(0.75).timeout
	var label: Label = bar.get_node("%CastingBarText")
	print("casting bar at %.2f showing '%s'" % [bar.value, label.text])
	_check(bar.visible and label.text == "Fireball", "the casting bar shows the spell")
	_check(bar.value > 0.3 and bar.value < 0.7, "the casting bar fills with the cast time")
	_capture("user://play_casting.png")
	session.spell_cast_finished.emit(session.get_player_guid(), FIREBALL, PackedInt64Array())
	await get_tree().create_timer(1.5).timeout
	_check(not bar.visible, "the casting bar fades after the cast")


# Hovering an action button and the target frame fills the tooltip the way the stock UI would.
func _check_tooltips(hud: Hud) -> void:
	var tooltip: GameTooltip = hud.get_node("%GameTooltip")
	var bar: MainMenuBar = hud.get_node("%MainMenuBar")
	var button: ActionButton = null
	for i: int in range(1, 13):
		var candidate: ActionButton = bar.get_node("%%ActionButton%d" % i)
		if candidate.spell() == 0:
			continue
		if button == null or not SpellText.describe(candidate.spell()).is_empty():
			button = candidate
	if button:
		button.mouse_entered.emit()
		await _frames(3)
		var first: String = _tooltip_text(tooltip)
		print("action tooltip: ", first.replace("\n", " | "))
		var spell_name: String = WowAssets.spells.spell_name(button.spell())
		_check(tooltip.visible and first.begins_with(spell_name), "an action button shows its tooltip")
		_capture("user://play_tooltip_spell.png")
		button.mouse_exited.emit()
		await _frames(2)
		_check(not tooltip.visible, "leaving the button hides the tooltip")
	var target: TargetFrame = hud.get_node("%TargetFrame")
	if target.visible:
		target.mouse_entered.emit()
		await _frames(3)
		print("unit tooltip: ", _tooltip_text(tooltip).replace("\n", " | "))
		_check(_tooltip_text(tooltip).contains("Level"), "the target frame shows a unit tooltip")
		_capture("user://play_tooltip_unit.png")
		target.mouse_exited.emit()
	var buff: WowButton = hud.get_node("%BuffFrame").get_node("%BuffButton0")
	if buff.visible:
		buff.mouse_entered.emit()
		await _frames(3)
		print("buff tooltip: ", _tooltip_text(tooltip).replace("\n", " | "))
		_capture("user://play_tooltip_buff.png")
		buff.mouse_exited.emit()


func _tooltip_text(tooltip: GameTooltip) -> String:
	var lines: PackedStringArray = []
	for label: Node in tooltip.find_children("*", "Label", true, false):
		if (label as Label).visible and not (label as Label).text.is_empty():
			lines.append((label as Label).text)
	return "\n".join(lines)


# A filled bottom-left slot shows that bar and lifts the casting bar; the slot is emptied after.
func _check_multi_bars(hud: Hud) -> void:
	const SLOT: int = 60
	const HEROIC_STRIKE: int = 78
	# Rage is stored times ten; with 15 rage the strike queues for the next swing instead of failing.
	const HEROIC_STRIKE_RAGE: int = 150
	var session: WowSession = WowClient.session
	if session.get_field(session.get_player_guid(), "UNIT_FIELD_POWER2") >= HEROIC_STRIKE_RAGE:
		print("skipping the error check: the player has rage left from an earlier fight")
		return
	var bar: Control = hud.get_node("%MainMenuBar").get_node("%MultiBarBottomLeft")
	var casting_bar: Control = hud.get_node("%CastingBarFrame")
	var resting_top: float = casting_bar.offset_top
	session.set_action_button(SLOT, HEROIC_STRIKE)
	await _frames(3)
	_check(bar.visible, "an action in slot 60 shows the bottom-left bar")
	_check(casting_bar.offset_top < resting_top, "the casting bar moves up over the bottom bars")
	_capture("user://play_multibars.png")
	session.set_action_button(SLOT, 0)
	await _frames(3)
	_check(not bar.visible, "emptying the bar hides it again")


# Heroic Strike on a distant unit fails; the server's reason shows in the stock wording.
func _check_errors(hud: Hud) -> void:
	const HEROIC_STRIKE: int = 78
	var session: WowSession = WowClient.session
	var errors: WowMessageFrame = hud.get_node("%UIErrorsFrame")
	var far: int = 0
	var player: Vector3 = session.get_object_position(session.get_player_guid())
	for guid: int in session.get_object_guids():
		if session.get_object_type(guid) == Entities.ObjectType.UNIT \
		and session.get_object_position(guid).distance_to(player) > 10.0:
			far = guid
			break
	if far == 0:
		print("skipping the error check: no unit out of melee range")
		return
	session.set_selection(far)
	session.cast_spell(HEROIC_STRIKE, far)
	var shown_by: int = Time.get_ticks_msec() + 5000
	while errors.get_child_count() == 0 and Time.get_ticks_msec() < shown_by:
		await get_tree().process_frame
	var text: String = (errors.get_child(0) as Label).text if errors.get_child_count() > 0 else ""
	print("error frame shows: '%s'" % text)
	_check(not text.is_empty(), "a failed cast shows its reason in the error frame")
	_capture("user://play_errors.png")


# The wowgd account is a GM, so .aura puts Mark of the Wild on the player without a trainer.
func _check_buffs(hud: Hud) -> void:
	const MARK_OF_THE_WILD: int = 1126
	var session: WowSession = WowClient.session
	session.set_selection(session.get_player_guid())
	session.send_chat(WowSession.CHAT_SAY, ".aura %d" % MARK_OF_THE_WILD)
	var button: Control = hud.get_node("%BuffFrame").get_node("%BuffButton0")
	var shown_by: int = Time.get_ticks_msec() + 5000
	while not button.visible and Time.get_ticks_msec() < shown_by:
		await get_tree().process_frame
	await _frames(5)
	_capture("user://play_buffs.png")
	_check(button.visible, "a buff the player casts shows in the buff frame")


func _on_movement_changed(
	opcode: String, _position: Vector3, _orientation: float, _flags: int,
	_fall_time_msec: int, _jump_velocity: Vector3, _ack_counter: int, _ack_tail: PackedByteArray,
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


func _check(condition: bool, what: String) -> bool:
	if not condition:
		_failures.append(what)
	return condition


func _finish(fatal: String) -> void:
	if not fatal.is_empty():
		_failures.append(fatal)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("play_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
