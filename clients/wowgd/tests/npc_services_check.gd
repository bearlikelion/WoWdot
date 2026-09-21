class_name NpcServicesCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
# A throwaway dwarf warrior (throwaway_character.gd): this spends money and finds flight points.
const CHARACTER: String = "Bolgrin"
const VENDOR: String = "Adlin Pridedrift"
const TRAINER: String = "Thran Khorman"
const VENDOR_SPOT: Vector3 = Vector3(-6226.67, 320.055, 383.143)
const TRAINER_SPOT: Vector3 = Vector3(-6084.77, 382.141, 395.626)
const THELSAMAR: Vector3 = Vector3(-5424.85, -2929.87, 347.645)
const IRONFORGE: Vector3 = Vector3(-4821.13, -1152.4, 502.295)
const STAND_OFF: float = 3.0
const VENDOR_ICON: int = 1
const TAXI_ICON: int = 2
const TRAINER_ICON: int = 3

var _failures: PackedStringArray = []
var _main: Main
var _panels: PanelManager


func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = "127.0.0.1"
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	_main.auto_character = CHARACTER
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var give_up: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _main.world == null or not _main.world.player().active:
		if Time.get_ticks_msec() > give_up:
			return _finish("never reached the world")
		await get_tree().process_frame
	await _frames(60)
	_panels = _main.world.hud().get_node("%UIPanels")
	var session: WowSession = WowClient.session
	session.send_chat(WowSession.CHAT_SAY, ".modify money 100000")
	await _frames(30)
	await _check_vendor()
	await _check_trainer()
	await _check_taxi()
	_finish("")


func _check_vendor() -> void:
	var merchant: MerchantFrame = _panels.get_node("%MerchantFrame")
	if not await _talk_to(VENDOR, VENDOR_SPOT, VENDOR_ICON):
		return
	await _frames(30)
	_check(merchant.visible, "a vendor opens the merchant frame")
	var first: Label = merchant.get_node("%MerchantItem1Name")
	print("merchant: %d items, first '%s'" % [(merchant.get("_items") as Array).size(), first.text])
	_capture("user://services_merchant.png")
	var money: int = Inventory.money()
	var entry: int = (merchant.get("_items") as Array)[0]["entry"]
	(merchant.get_node("%MerchantItem1ItemButton") as ItemButton).right_clicked.emit()
	await _frames(40)
	print("bought: money %d -> %d" % [money, Inventory.money()])
	_check(Inventory.money() < money, "right-clicking a merchant item buys it")
	var found: Vector2i = Inventory.find_item(entry)
	_check(found.x >= 0, "the bought item is in the bags")
	if found.x >= 0:
		_main.world.hud().use_container_item(found.x, found.y)
		await _frames(40)
		(merchant.get_node("%MerchantFrameTab2") as BaseButton).pressed.emit()
		await _frames(10)
		var sold: Label = merchant.get_node("%MerchantItem1Name")
		print("buyback: '%s'" % sold.text)
		_check(not sold.text.is_empty(), "a sold item shows under buyback")
		_capture("user://services_buyback.png")
	_panels.hide_panel(merchant)


func _check_trainer() -> void:
	var trainer: ClassTrainerFrame = _panels.get_node("%ClassTrainerFrame")
	if not await _talk_to(TRAINER, TRAINER_SPOT, TRAINER_ICON):
		return
	await _frames(30)
	_check(trainer.visible, "a trainer opens the trainer frame")
	var entries: Array = trainer.get("_entries")
	print("trainer: %d rows, first '%s', selected '%s'" % [
		entries.size(), entries[0].get("name", "") if not entries.is_empty() else "",
		(trainer.get_node("%ClassTrainerSkillName") as Label).text,
	])
	_check(not entries.is_empty(), "the trainer lists services")
	_capture("user://services_trainer.png")
	_panels.hide_panel(trainer)


# Both flight points get found on foot first, then the flight master flies between them.
func _check_taxi() -> void:
	var taxi: TaxiFrame = _panels.get_node("%TaxiFrame")
	await _teleport(THELSAMAR)
	await _talk_to_nearest_flight_master()
	await _teleport(IRONFORGE)
	await _talk_to_nearest_flight_master()
	if not await _talk_to_nearest_flight_master(true):
		return
	await _frames(30)
	_check(taxi.visible, "a flight master opens the flight map")
	var buttons: Dictionary = taxi.get("_buttons")
	print("taxi: %d nodes shown" % buttons.size())
	_capture("user://services_taxi.png")
	var destination: int = 0
	for node: int in buttons:
		if taxi.get("_types")[node] == TaxiFrame.NodeType.REACHABLE:
			destination = node
	_check(destination != 0, "a found flight point is reachable")
	if destination == 0:
		return
	var button: WowButton = buttons[destination]
	button.mouse_entered.emit()
	await _frames(10)
	_capture("user://services_taxi_route.png")
	button.pressed.emit()
	await _frames(300)
	var player: Player = _main.world.player()
	var flying: bool = not (player.get("_path") as PackedVector3Array).is_empty()
	var mount: int = WowClient.session.get_field(
		WowClient.session.get_player_guid(), "UNIT_FIELD_MOUNTDISPLAYID"
	)
	print("flying: path %s, mount display %d" % [flying, mount])
	_check(flying and mount != 0, "taking a flight mounts the player on the path")
	_capture("user://services_flight.png")


func _talk_to_nearest_flight_master(open_map: bool = false) -> bool:
	var session: WowSession = WowClient.session
	var nearest: int = 0
	var best: float = INF
	var here: Vector3 = session.get_object_position(session.get_player_guid())
	for guid: int in session.get_object_guids():
		if session.get_field(guid, "UNIT_NPC_FLAGS") & 0x8 == 0:
			continue
		var distance: float = session.get_object_position(guid).distance_to(here)
		if distance < best:
			best = distance
			nearest = guid
	if nearest == 0:
		_check(false, "a flight master is nearby")
		return false
	var taxi: TaxiFrame = _panels.get_node("%TaxiFrame")
	var gossip: GossipFrame = _panels.get_node("%GossipFrame")
	# Spawn points drift from where the NPC stands, and talking needs a few yards at most.
	if best > STAND_OFF:
		await _teleport(session.get_object_position(nearest) + Vector3(STAND_OFF, 0.0, 0.0))
	NpcDialog.interact(nearest)
	await _until(func() -> bool: return gossip.visible or taxi.visible, 5000)
	if not open_map:
		_panels.close_windows()
		return true
	if gossip.visible and not await _pick_gossip_option(TAXI_ICON):
		return false
	return await _until(func() -> bool: return taxi.visible, 5000)


func _until(condition: Callable, timeout_msec: int) -> bool:
	var give_up: int = Time.get_ticks_msec() + timeout_msec
	while not condition.call():
		if Time.get_ticks_msec() > give_up:
			return false
		await get_tree().process_frame
	return true


# Stands in front of the named NPC, talks to it, and picks the service from gossip if one opens.
func _talk_to(npc_name: String, spot: Vector3, icon: int) -> bool:
	var session: WowSession = WowClient.session
	await _teleport(spot)
	var npc: int = 0
	var give_up: int = Time.get_ticks_msec() + 10000
	while npc == 0 and Time.get_ticks_msec() < give_up:
		# Names arrive with the creature queries that asking for them sends.
		for guid: int in session.get_object_guids():
			if session.get_object_name(guid) == npc_name:
				npc = guid
		await get_tree().process_frame
	if npc == 0:
		_check(false, "%s is in view" % npc_name)
		return false
	var facing: float = session.get_object_orientation(npc)
	await _teleport(
		session.get_object_position(npc) + Vector3(cos(facing), sin(facing), 0.0) * STAND_OFF
	)
	NpcDialog.interact(npc)
	await _frames(60)
	return await _pick_gossip_option(icon)


func _pick_gossip_option(icon: int) -> bool:
	var gossip: GossipFrame = _panels.get_node("%GossipFrame")
	if not gossip.visible:
		return true
	var rows: Array = gossip.get("_rows")
	for i: int in rows.size():
		if rows[i]["kind"] == GossipFrame.Row.OPTION and rows[i]["icon"] == icon:
			(gossip.get_node("%%GossipTitleButton%d" % (i + 1)) as BaseButton).pressed.emit()
			await _frames(60)
			return true
	_check(false, "gossip offers option icon %d" % icon)
	return false


func _teleport(spot: Vector3) -> void:
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
	print("npc_services_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
