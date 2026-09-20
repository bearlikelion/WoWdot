class_name ItemMoveCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const MOVE_WAIT_MSEC: int = 5000
# Small Brown Pouch, a six slot bag, so the check has a container to move an item into.
const POUCH_ENTRY: int = 4496
# Linen Cloth, which stacks, so a split has something to divide.
const CLOTH_ENTRY: int = 2589
const CLOTH_COUNT: int = 5
const SPLIT_COUNT: int = 2

var _failures: PackedStringArray = []
var _main: Main


# Moves an equipped item into the backpack, around it and back, the way a drag would.
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
	await _frames(60)
	await _wear_a_bag()
	var worn: Vector2i = _worn_slot()
	var free: Vector2i = _free_pack_slot()
	if worn.x < 0 or free.x < 0:
		return _finish("no equipped item and a free backpack slot to move between")
	var item: int = Inventory.item_at(worn)
	print("moving item %d from slot %d to pack slot %d" % [item, worn.y, free.y])
	await _move(worn, free, item)
	_check(Inventory.item_at(free) == item, "an equipped item unequips into the backpack")
	var second: Vector2i = _free_pack_slot()
	if second.x >= 0:
		await _move(free, second, item)
		_check(Inventory.item_at(second) == item, "and moves between two backpack slots")
		await _move(second, free, item)
	var bag: Vector2i = _free_bag_slot()
	if bag.x >= 0:
		await _move(free, bag, item)
		_check(Inventory.item_at(bag) == item, "and into a worn bag")
		await _move(bag, free, item)
	else:
		print("no worn bag with a free slot, CMSG_SWAP_ITEM is not covered")
	await _move(free, worn, item)
	_check(Inventory.item_at(worn) == item, "and goes back on the character")
	await _split_and_destroy()
	_finish("")


# A stack divides into two, and the smaller half can be thrown away.
func _split_and_destroy() -> void:
	var found: Vector2i = await _added(CLOTH_ENTRY, CLOTH_COUNT)
	if found.x < 0:
		print("no stackable item could be added, split and destroy stay uncovered")
		return
	var from: Vector2i = Inventory.wire_address(found.x, found.y)
	# Earlier runs leave cloth behind, so the stack to divide is whatever is there now.
	var stack: int = Inventory.stack_count(Inventory.item_at(from))
	var to: Vector2i = _free_pack_slot()
	if to == from:
		return _failures.append("no free slot to split into")
	Inventory.split(from, to, SPLIT_COUNT)
	await _until(func() -> bool: return Inventory.item_at(to) != 0)
	_check(
		Inventory.stack_count(Inventory.item_at(to)) == SPLIT_COUNT,
		"a stack splits into the count asked for",
	)
	_check(
		Inventory.stack_count(Inventory.item_at(from)) == stack - SPLIT_COUNT,
		"and the rest stays behind",
	)
	Inventory.destroy(to, SPLIT_COUNT)
	await _until(func() -> bool: return Inventory.item_at(to) == 0)
	_check(Inventory.item_at(to) == 0, "and a stack can be destroyed")


# Waits on the count, not on the item, since an earlier run may have left some behind.
func _added(entry: int, count: int) -> Vector2i:
	var wanted: int = Inventory.item_count(entry) + count
	WowClient.session.send_chat(WowSession.CHAT_SAY, ".additem %d %d" % [entry, count])
	await _until(func() -> bool: return Inventory.item_count(entry) >= wanted)
	return Inventory.find_item(entry)


func _until(done: Callable) -> void:
	var deadline: int = Time.get_ticks_msec() + MOVE_WAIT_MSEC
	while not done.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await _frames(5)


# The starting kit has no bag, so CMSG_SWAP_ITEM has nothing to aim at until one is worn.
func _wear_a_bag() -> void:
	if _free_bag_slot().x >= 0:
		return
	var found: Vector2i = await _added(POUCH_ENTRY, 1)
	if found.x < 0:
		print("no bag could be added, CMSG_SWAP_ITEM stays uncovered")
		return
	var pouch: Vector2i = Inventory.wire_address(found.x, found.y)
	await _move(pouch, Vector2i(Inventory.WIRE_BACKPACK, Inventory.Slot.BAG_1),
		Inventory.item_at(pouch))


# Waits for the item to leave the slot it was in, since the server answers with a field update.
func _move(from: Vector2i, to: Vector2i, item: int) -> void:
	Inventory.move(from, to)
	var until: int = Time.get_ticks_msec() + MOVE_WAIT_MSEC
	while Inventory.item_at(from) == item and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	await _frames(5)


func _worn_slot() -> Vector2i:
	for slot: Inventory.Slot in [
		Inventory.Slot.SHIRT, Inventory.Slot.FEET, Inventory.Slot.LEGS, Inventory.Slot.MAIN_HAND,
	]:
		var address: Vector2i = Vector2i(Inventory.WIRE_BACKPACK, slot)
		if Inventory.item_at(address) != 0:
			return address
	return -Vector2i.ONE


func _free_pack_slot() -> Vector2i:
	for slot: int in Inventory.BACKPACK_SLOTS:
		var address: Vector2i = Inventory.wire_address(Inventory.BACKPACK, slot)
		if Inventory.item_at(address) == 0:
			return address
	return -Vector2i.ONE


func _free_bag_slot() -> Vector2i:
	for bag: int in range(1, Inventory.BAG_COUNT + 1):
		for slot: int in Inventory.container_size(bag):
			var address: Vector2i = Inventory.wire_address(bag, slot)
			if Inventory.item_at(address) == 0:
				return address
	return -Vector2i.ONE


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
	print("item_move_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
