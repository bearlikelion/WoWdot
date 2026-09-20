class_name EffectCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 150000
const STAND_OFF: float = 8.0
const TYPE_UNIT: int = 3
const CRITTER_HEALTH: int = 30
const FIREBALL: int = 133
# A mage knows Fireball from the first level; the shared test character is a warrior.
const MAGE: String = "Wiztest"
const MAGE_LEVEL: int = 10
# Teleport hops allowed while closing on a creature that wanders, and the range they end at.
const HOPS: int = 5
const NEAR: float = 25.0
# Creatures killed while hunting for one that drops loot.
const CORPSES: int = 4
# Rank 1 fireballs it takes to put a starting-zone beast down.
const CASTS: int = 5

var _failures: PackedStringArray = []
var _main: Main


# Throws a fireball at a creature, then kills it and watches the corpse sparkle.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = "127.0.0.1"
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	_main.auto_character = MAGE
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var give_up: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _main.world == null or not _main.world.player().active:
		if Time.get_ticks_msec() > give_up:
			return _finish("never reached the world")
		await get_tree().process_frame
	await _frames(120)
	var session: WowSession = WowClient.session
	var effects: SpellEffects = _main.world.get_node("SpellEffects")
	var home: Vector3 = session.get_object_position(session.get_player_guid())
	for command: String in [
		".character level %s %d" % [MAGE, MAGE_LEVEL], ".modify hp 5000", ".modify mana 5000",
	]:
		session.send_chat(WowSession.CHAT_SAY, command)
		await _frames(30)
	var prey: int = 0
	for hop: int in HOPS:
		prey = _nearest_prey()
		if prey == 0:
			await _frames(60)
			continue
		if _yards_to(prey) <= NEAR:
			break
		await _go(WowClient.session.get_object_position(prey) + Vector3(STAND_OFF, 0.0, 0.0))
	if prey == 0 or _yards_to(prey) > NEAR:
		return _finish("no creature came within %d yards" % NEAR)
	print("aiming at %s, %.1f yards off" % [session.get_object_name(prey), _yards_to(prey)])
	_main.world.select(prey)
	await _frames(20)
	if _main.world.hud().target() != prey:
		return _finish("the target frame never took the prey")
	session.spell_cast_failed.connect(func(_caster: int, spell: int, reason: int) -> void:
		print("  cast of %d failed: %d" % [spell, reason])
	)
	var flew: bool = false
	var dressed: bool = false
	var posed: bool = false
	for cast: int in CASTS:
		if session.get_field(prey, "UNIT_FIELD_HEALTH") == 0:
			break
		session.send_chat(WowSession.CHAT_SAY, ".modify mana 5000")
		await _frames(10)
		print("  cast %d from %.1f yards" % [cast, _yards_to(prey)])
		_main.world.call("_use_spell", FIREBALL)
		for frame: int in 300:
			dressed = dressed or not (effects.get("_casting") as Dictionary).is_empty()
			posed = posed or _playing(_main.world.player().model(), "ReadySpellDirected")
			if not (effects.get("_missiles") as Array).is_empty():
				if not flew:
					_capture("user://spell_missile.png")
				flew = true
			await get_tree().process_frame
	# Only a corpse that dropped something sparkles, and not every creature carries loot.
	var sparkled: bool = false
	for attempt: int in CORPSES:
		var corpse: int = prey if attempt == 0 else _nearest_prey()
		if corpse == 0:
			break
		_main.world.select(corpse)
		await _frames(20)
		session.send_chat(WowSession.CHAT_SAY, ".die")
		await _frames(120)
		if not _main.world.call("_is_lootable", corpse):
			print("  %s dropped nothing" % session.get_object_name(corpse))
			continue
		sparkled = (effects.get("_sparkles") as Dictionary).has(corpse)
		print("  %s is lootable, sparkling: %s" % [session.get_object_name(corpse), sparkled])
		if sparkled:
			_capture("user://loot_sparkle.png")
		break
	_check(sparkled, "a lootable corpse sparkles")
	await _go(home)
	_finish("")


# Yards between the player as drawn and a unit; the object store's own copy goes stale.
func _yards_to(guid: int) -> float:
	var here: Vector3 = WowCoords.from_godot(_main.world.player().global_position)
	return here.distance_to(WowClient.session.get_object_position(guid))


func _playing(model: Node3D, clip: String) -> bool:
	var player: AnimationPlayer = model.get_node_or_null("AnimationPlayer") if model else null
	return player != null and player.current_animation == clip


func _nearest_prey() -> int:
	var session: WowSession = WowClient.session
	var player: int = session.get_player_guid()
	var here: Vector3 = session.get_object_position(player)
	var nearest: int = 0
	var best: float = INF
	for guid: int in session.get_object_guids():
		if session.get_object_type(guid) != TYPE_UNIT \
		or session.get_field(guid, "UNIT_FIELD_HEALTH") == 0 \
		or session.get_field(guid, "UNIT_FIELD_MAXHEALTH") < CRITTER_HEALTH:
			continue
		if UnitReaction.between(session, player, guid) == UnitReaction.Reaction.FRIENDLY \
		or session.get_field(guid, "UNIT_NPC_FLAGS") != 0:
			continue
		var distance: float = session.get_object_position(guid).distance_to(here)
		if distance < best:
			best = distance
			nearest = guid
	return nearest


func _go(spot: Vector3) -> void:
	WowClient.session.send_chat(
		WowSession.CHAT_SAY, ".go xyz %f %f %f" % [spot.x, spot.y, spot.z]
	)
	await _frames(150)


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
	print("effect_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
