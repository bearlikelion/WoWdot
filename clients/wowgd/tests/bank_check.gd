class_name BankCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 15000
# The Ironforge bank, where the nearest bankers stand.
const IRONFORGE_BANK: Vector3 = Vector3(-4877.4, -990.0, 504.0)
const HOME: Vector3 = Vector3(-6248.77, 317.339, 382.778)
# UNIT_NPC_FLAG_BANKER, since bankers carry their own names.
const NPC_FLAG_BANKER: int = 0x100
# Small Brown Pouch, six slots, so a bank bag slot has something to hold.
const POUCH_ENTRY: int = 4496

var _failures: PackedStringArray = []
var _main: Main


# Opens a banker's vault, puts an item in and takes it out again.
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
	var session: WowSession = WowClient.session
	var hud: Hud = _main.world.hud()
	var bank: BankFrame = hud.find_child("BankFrame", true, false)
	await _teleport(IRONFORGE_BANK)
	var banker: int = await _nearest_banker()
	if banker == 0:
		await _teleport(HOME)
		return _finish("no banker in the Ironforge bank")
	# The banker has to be within interaction range, so the check stands on its spot.
	await _teleport(session.get_object_position(banker))
	bank.activate(banker)
	var opened: bool = await _until(func() -> bool: return bank.visible)
	_check(opened, "a banker opens the bank")
	if not opened:
		await _teleport(HOME)
		return _finish("the bank never opened")

	var stored: Vector2i = _first_item()
	var item: int = Inventory.container_item(stored.x, stored.y)
	var entry: int = Inventory.entry(item)
	_check(entry != 0, "the player carries something to bank")
	hud.use_container_item(stored.x, stored.y)
	var banked: bool = await _until(func() -> bool: return _bank_slot_of(entry) >= 0)
	_check(banked, "right-clicking a bag item banks it")
	if banked:
		var slot: int = _bank_slot_of(entry)
		(bank.get_node("%%BankFrameItem%d" % (slot + 1)) as BaseButton).pressed.emit()
		var back: bool = await _until(func() -> bool: return _bank_slot_of(entry) < 0)
		_check(back, "clicking a bank slot takes the item back")
	await _check_bank_bag(bank)
	(bank.get_node("%BankCloseButton") as BaseButton).pressed.emit()
	await _frames(10)
	_check(not bank.visible, "the close button shuts the bank")
	_check(_open_bank_bags(hud) == 0, "and its bags close with it")
	_check(session.get_state() == WowSession.STATE_IN_WORLD, "the server kept the session")
	await _teleport(HOME)
	_finish("")


# The first bank bag slot takes a bag, which then opens and holds an item like any other.
func _check_bank_bag(bank: BankFrame) -> void:
	WowClient.session.send_chat(WowSession.CHAT_SAY, ".modify money 1000000")
	await _frames(30)
	if bank.bought_bags() < BankFrame.BANK_BAGS:
		(bank.get_node("%BankFramePurchaseButton") as BaseButton).pressed.emit()
		await _until(func() -> bool: return bank.bought_bags() > 0)
	_check(bank.bought_bags() > 0, "a bank bag slot can be bought")
	if bank.bought_bags() == 0:
		return
	var pouch: Vector2i = await _added(POUCH_ENTRY)
	if pouch.x < 0:
		print("no bag could be added, the bank bag slot stays uncovered")
		return
	Inventory.move(Inventory.wire_address(pouch.x, pouch.y), _bank_bag_address(0))
	var held: bool = await _until(func() -> bool: return Inventory.bank_bag(0) != 0)
	_check(held, "a bag goes into a bank bag slot")
	if not held:
		return
	_check(Inventory.container_size(Inventory.BANK_BAG_FIRST) > 0, "and reports its size")
	var hud: Hud = _main.world.hud()
	bank.bag_toggled.emit(Inventory.BANK_BAG_FIRST)
	await _frames(10)
	_check(_open_bank_bags(hud) == 1, "and opens like any other bag")
	var carried: Vector2i = _first_item()
	Inventory.move(
		Inventory.wire_address(carried.x, carried.y),
		Inventory.wire_address(Inventory.BANK_BAG_FIRST, 0),
	)
	var inside: bool = await _until(
		func() -> bool: return Inventory.container_item(Inventory.BANK_BAG_FIRST, 0) != 0
	)
	_check(inside, "and holds an item")
	if inside:
		Inventory.move(
			Inventory.wire_address(Inventory.BANK_BAG_FIRST, 0),
			Inventory.wire_address(carried.x, carried.y),
		)
		await _until(
			func() -> bool: return Inventory.container_item(Inventory.BANK_BAG_FIRST, 0) == 0
		)
	Inventory.move(_bank_bag_address(0), Inventory.wire_address(pouch.x, pouch.y))
	await _until(func() -> bool: return Inventory.bank_bag(0) == 0)


func _bank_bag_address(index: int) -> Vector2i:
	return Vector2i(Inventory.WIRE_BACKPACK, Inventory.WIRE_BANK_BAG_START + index)


func _open_bank_bags(hud: Hud) -> int:
	var open: int = 0
	var frames: Array[Node] = hud.find_children("*", "ContainerFrame", true, false)
	for frame: ContainerFrame in frames:
		open += int(frame.visible and frame.bag >= Inventory.BANK_BAG_FIRST)
	return open


func _added(entry: int) -> Vector2i:
	var wanted: int = Inventory.item_count(entry) + 1
	WowClient.session.send_chat(WowSession.CHAT_SAY, ".additem %d 1" % entry)
	await _until(func() -> bool: return Inventory.item_count(entry) >= wanted)
	return Inventory.find_item(entry)


func _bank_slot_of(entry: int) -> int:
	var session: WowSession = WowClient.session
	var first: int = session.field_index("PLAYER_FIELD_BANK_SLOT_1")
	for i: int in BankFrame.BANK_SLOTS:
		var item: int = session.get_field_guid(session.get_player_guid(), first + i * 2)
		if item != 0 and Inventory.entry(item) == entry:
			return i
	return -1


func _first_item() -> Vector2i:
	for bag: int in Inventory.BAG_COUNT + 1:
		for slot: int in Inventory.container_size(bag):
			if Inventory.container_item(bag, slot) != 0:
				return Vector2i(bag, slot)
	return Vector2i(-1, -1)


func _nearest_banker() -> int:
	await _frames(60)
	var session: WowSession = WowClient.session
	var here: Vector3 = session.get_object_position(session.get_player_guid())
	var best: int = 0
	var best_range: float = INF
	for guid: int in session.get_object_guids():
		if not session.get_field(guid, "UNIT_NPC_FLAGS") & NPC_FLAG_BANKER:
			continue
		var away: float = session.get_object_position(guid).distance_to(here)
		if away < best_range:
			best_range = away
			best = guid
	return best


func _teleport(wow_position: Vector3) -> void:
	WowClient.session.send_chat(
		WowSession.CHAT_SAY, ".go xyz %f %f %f" % [wow_position.x, wow_position.y, wow_position.z]
	)
	await _frames(30)
	var loaded_by: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while not _main.world.player().active and Time.get_ticks_msec() < loaded_by:
		await get_tree().process_frame
	await _frames(60)


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
	print("bank_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
