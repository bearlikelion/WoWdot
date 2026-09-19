class_name CombatCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const FIGHT_MSEC: int = 20000
const TARGET_NAME: String = "Young Wolf"
const MELEE_GAP: float = 1.5
# Warriors keep their Battle Stance bar in slots 72 to 83, with Attack first.
const ATTACK_SLOT: int = 72
const FACING_TOLERANCE: float = deg_to_rad(30.0)

var _failures: PackedStringArray = []
var _main: Main
var _swings: Dictionary[String, int] = {}
var _clips: Dictionary[String, int] = {}
var _wolf_node: Node3D
# The widest angle between where the wolf looks and where the player is, over its swings.
var _worst_facing: float = 0.0


# Walks up to a wolf, auto-attacks it from the action bar and records the clips the fight plays.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	_main.auto_character = "Tessaline"
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var tree: SceneTree = get_tree()
	var ready_at: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _main.world == null or not _main.world.player().active:
		if Time.get_ticks_msec() > ready_at:
			return _finish("never reached the world")
		await tree.process_frame
	await _frames(60)
	var session: WowSession = WowClient.session
	var wolf: int = await _find(TARGET_NAME)
	if wolf == 0:
		return _finish("no %s nearby" % TARGET_NAME)
	var entities: Entities = _main.world.get_node("Entities")
	var wolf_node: Node3D = entities.unit_node(wolf)
	_wolf_node = wolf_node
	var player: Player = _main.world.player()
	var to_wolf: Vector3 = wolf_node.global_position - player.global_position
	to_wolf.y = 0.0
	player.global_position = wolf_node.global_position - to_wolf.normalized() * MELEE_GAP
	player.rotation.y = atan2(-to_wolf.x, -to_wolf.z)
	player.movement_changed.emit(
		"MSG_MOVE_HEARTBEAT", player.global_position, player.orientation(), 0, 0, Vector3.ZERO
	)
	await _frames(10)
	_main.world.select(wolf)
	session.melee_swing.connect(_on_melee_swing)
	_watch(wolf_node)
	_watch(player.get_node("Model").get_child(0))
	_main.world.hud().action_used.emit(ATTACK_SLOT)

	var fight_until: int = Time.get_ticks_msec() + FIGHT_MSEC
	var captured: bool = false
	while Time.get_ticks_msec() < fight_until and session.get_field(wolf, "UNIT_FIELD_HEALTH") > 0:
		await tree.process_frame
		if not captured and _swings.size() >= 2:
			captured = true
			get_viewport().get_texture().get_image().save_png("user://combat.png")
	await _frames(90)
	get_viewport().get_texture().get_image().save_png("user://combat_end.png")
	print("swings: ", _swings, " clips: ", _clips, " facing: ", rad_to_deg(_worst_facing))
	_check(_swings.get("player", 0) > 0, "the player swings at the wolf")
	var attacked: bool = _clips.keys().any(
		func(clip: String) -> bool: return clip.begins_with("Attack")
	)
	_check(attacked, "a swing plays an attack clip")
	if _swings.get("other", 0) > 0:
		_check(_worst_facing < FACING_TOLERANCE, "the wolf faces the player when it swings")
	if session.get_field(wolf, "UNIT_FIELD_HEALTH") == 0:
		_check(_clips.has("Death"), "the wolf plays its death clip")
	_finish("")


# Asks for every unit's name first, then picks the nearest living match once the answers are in.
func _find(creature_name: String) -> int:
	var session: WowSession = WowClient.session
	var units: Array[int] = []
	for guid: int in session.get_object_guids():
		if session.get_object_type(guid) == Entities.ObjectType.UNIT:
			session.get_object_name(guid)
			units.append(guid)
	await _frames(60)
	var player: Vector3 = WowCoords.from_godot(_main.world.player().global_position)
	var best: int = 0
	var best_distance: float = INF
	for guid: int in units:
		var distance: float = session.get_object_position(guid).distance_to(player)
		if session.get_object_name(guid) == creature_name and distance < best_distance \
		and session.get_field(guid, "UNIT_FIELD_HEALTH") > 0:
			best = guid
			best_distance = distance
	return best


func _watch(model: Node3D) -> void:
	var player: AnimationPlayer = model.get_node_or_null("AnimationPlayer")
	if player:
		player.current_animation_changed.connect(_on_clip_changed)


func _on_clip_changed(clip: String) -> void:
	_clips[clip] = _clips.get(clip, 0) + 1


func _on_melee_swing(
	attacker: int, _victim: int, _damage: int, _hit_info: int, _victim_state: int,
) -> void:
	var who: String = "player" if attacker == WowClient.session.get_player_guid() else "other"
	_swings[who] = _swings.get(who, 0) + 1
	if who == "other":
		var to_player: Vector3 = _main.world.player().global_position - _wolf_node.global_position
		var forward: Vector3 = -_wolf_node.global_basis.z
		var angle: float = Vector2(forward.x, forward.z).angle_to(Vector2(to_player.x, to_player.z))
		_worst_facing = maxf(_worst_facing, absf(angle))


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
	print("combat_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
