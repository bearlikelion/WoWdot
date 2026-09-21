class_name LootCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STAND_OFF: float = 2.0
const TYPE_UNIT: int = 3
# Rabbits and other critters drop nothing.
const CRITTER_HEALTH: int = 30

var _failures: PackedStringArray = []
var _main: Main


# Kills the nearest hostile creature with the GM .die command, then loots the corpse empty.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = "127.0.0.1"
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
	await _frames(120)
	var session: WowSession = WowClient.session
	var home: Vector3 = session.get_object_position(session.get_player_guid())
	var loot: LootFrame = _main.world.hud().get_node("%UIPanels").get_node("%LootFrame")
	var looted: bool = false
	for attempt: int in 4:
		var prey: int = _nearest_prey()
		if prey == 0:
			break
		print("killing %s" % session.get_object_name(prey))
		await _go(session.get_object_position(prey) + Vector3(STAND_OFF, 0.0, 0.0))
		_main.world.select(prey)
		await _frames(20)
		session.send_chat(WowSession.CHAT_SAY, ".die")
		await _frames(90)
		await _go(session.get_object_position(prey) + Vector3(STAND_OFF, 0.0, 0.0))
		if not _main.world.call("_is_lootable", prey):
			print("  nothing dropped")
			continue
		LootFrame.loot(prey)
		await _frames(60)
		_check(loot.visible, "looting a corpse opens the loot frame")
		if not loot.visible:
			break
		var slots: Array = loot.get("_slots")
		print("  loot slots: %s, first row '%s'" % [
			slots, (loot.get_node("%LootButton1").get_node("%Text") as Label).text,
		])
		_capture("user://loot_frame.png")
		var money: int = Inventory.money()
		var had_coin: bool = LootFrame.COIN_SLOT in slots
		while loot.visible and not (loot.get("_slots") as Array).is_empty():
			(loot.get_node("%LootButton1") as ItemButton).pressed.emit()
			await _frames(30)
		_check(not loot.visible, "taking everything closes the loot frame")
		if had_coin:
			_check(Inventory.money() > money, "looted money reaches the purse")
		looted = true
		break
	_check(looted, "a killed creature could be looted")
	await _go(home)
	_finish("")


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
	if DisplayServer.get_name() == "headless":
		return
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
	print("loot_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
