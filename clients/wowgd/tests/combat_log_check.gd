class_name CombatLogCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const FIGHT_MSEC: int = 25000
const SEARCH_YARDS: float = 40.0
const CRITTER: int = 8
const MELEE_GAP: float = 1.5
# Warriors keep their Battle Stance bar in slots 72 to 83, with Attack first.
const ATTACK_SLOT: int = 72

var _failures: PackedStringArray = []
var _main: Main
var _events: Array[CombatEvents.CombatEvent] = []


# Fights the nearest hostile creature and checks what the combat log, text and feedback made of it.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
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
	var mob: int = await _find_hostile()
	if mob == 0:
		return _finish("no creature to fight within %d yards" % SEARCH_YARDS)
	print("fighting ", session.get_object_name(mob))
	WowClient.combat.logged.connect(_events.append)
	var entities: Entities = _main.world.get_node("Entities")
	var mob_node: Node3D = entities.unit_node(mob)
	var player: Player = _main.world.player()
	var to_mob: Vector3 = mob_node.global_position - player.global_position
	to_mob.y = 0.0
	player.global_position = mob_node.global_position - to_mob.normalized() * MELEE_GAP
	player.rotation.y = atan2(-to_mob.x, -to_mob.z)
	player.movement_changed.emit(
		"MSG_MOVE_HEARTBEAT", player.global_position, player.orientation(), 0, 0, Vector3.ZERO,
		-1, PackedByteArray(),
	)
	await _frames(10)
	_main.world.select(mob)
	_main.world.hud().action_used.emit(ATTACK_SLOT)
	var floating: Node3D = _main.world.get_node("FloatingCombatText")
	var scrolling: Control = _main.world.hud().get_node("%UIParent/CombatText")
	var feedback: Label = _main.world.hud().get_node("%PlayerFrame").get_node("%PlayerHitIndicator")
	var seen: Dictionary[String, bool] = {}
	var fight_until: int = Time.get_ticks_msec() + FIGHT_MSEC
	while Time.get_ticks_msec() < fight_until and session.get_field(mob, "UNIT_FIELD_HEALTH") > 0:
		await tree.process_frame
		if floating.get_child_count() > 0:
			seen["floating"] = true
		if scrolling.get_children().any(func(line: Label) -> bool: return line.visible):
			seen["scrolling"] = true
		if feedback.visible and feedback.modulate.a > 0.9:
			seen["feedback"] = true
		if seen.size() == 3 and not seen.has("shot"):
			seen["shot"] = true
			get_viewport().get_texture().get_image().save_png("user://combat_text.png")
	await _frames(60)
	_check(seen.has("floating"), "the player's hits float over the target")
	_check(seen.has("scrolling"), "damage taken scrolls up the middle of the screen")
	_check(seen.has("feedback"), "damage taken flashes over the player portrait")

	var me: int = session.get_player_guid()
	var dealt: Array[CombatEvents.CombatEvent] = _events.filter(
		func(e: CombatEvents.CombatEvent) -> bool: return e.source == me and e.target == mob
	)
	var taken: Array[CombatEvents.CombatEvent] = _events.filter(
		func(e: CombatEvents.CombatEvent) -> bool: return e.source == mob and e.target == me
	)
	for event: CombatEvents.CombatEvent in _events:
		print("  ", CombatLogFrame.format(event))
	_check(not dealt.is_empty(), "the player's attacks are logged")
	_check(not taken.is_empty(), "the creature's attacks are logged")
	_check(dealt.all(func(e: CombatEvents.CombatEvent) -> bool:
		return e.kind not in [CombatEvents.Kind.MELEE, CombatEvents.Kind.SPELL] \
		or e.outcome != CombatEvents.Outcome.HIT or e.amount > 0),
		"every landed hit carries its damage")
	var combat_log: CombatLogFrame = _main.world.hud().get_node("%ChatFrame2")
	var first_line: String = CombatLogFrame.format(dealt[0]) if not dealt.is_empty() else "?"
	_check(combat_log.all_text().contains(first_line), "the Combat Log tab shows the fight")
	combat_log.tab_selected.emit()
	# Wayland cannot warp the cursor, so hold the dock in its hovered state for the screenshot.
	_main.world.hud().set_process(false)
	for frame: DockedChatFrame in [_main.world.hud().get_node("%ChatFrame1"), combat_log]:
		frame.set_hovered(true)
	await _frames(40)
	get_viewport().get_texture().get_image().save_png("user://combat_log.png")
	_finish("")


# The nearest creature that will fight back: not friendly and not a critter.
func _find_hostile() -> int:
	var session: WowSession = WowClient.session
	var me: int = session.get_player_guid()
	var units: Array[int] = []
	for guid: int in session.get_object_guids():
		if session.get_object_type(guid) == Entities.ObjectType.UNIT:
			session.get_object_name(guid)
			units.append(guid)
	await _frames(60)
	var here: Vector3 = session.get_object_position(me)
	var best: int = 0
	var best_distance: float = SEARCH_YARDS
	for guid: int in units:
		if session.get_field(guid, "UNIT_FIELD_HEALTH") <= 0 \
		or session.get_creature_info(guid).get("type", CRITTER) == CRITTER \
		or UnitReaction.between(session, me, guid) == UnitReaction.Reaction.FRIENDLY:
			continue
		var distance: float = session.get_object_position(guid).distance_to(here)
		if distance < best_distance:
			best = guid
			best_distance = distance
	return best


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
	print("combat_log_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
