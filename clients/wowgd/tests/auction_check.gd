class_name AuctionCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 15000
# Auctioneer Buckler in the Ironforge auction house, and Coldridge Valley to come home to.
const AUCTIONEER: Vector3 = Vector3(-4948.0, -901.5, 505.2)
const HOME: Vector3 = Vector3(-6248.77, 317.339, 382.778)
const NPC_FLAG_AUCTIONEER: int = 0x1000
const PURSE: int = 100000
# Linen Cloth: cheap, stackable and not soulbound, so it can always go up for sale.
const LINEN_CLOTH: int = 2589

var _failures: PackedStringArray = []
var _main: Main


# Opens the auction house, puts an item up for sale, finds it among its own auctions and cancels it.
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
	var house: AuctionFrame = hud.find_child("AuctionFrame", true, false)
	session.send_chat(WowSession.CHAT_SAY, ".modify money %d" % PURSE)
	await _teleport(AUCTIONEER)
	var auctioneer: int = await _nearest_auctioneer()
	if auctioneer == 0:
		await _teleport(HOME)
		return _finish("no auctioneer in the Ironforge auction house")
	await _teleport(session.get_object_position(auctioneer))
	hud.open_auction_house(auctioneer)
	var opened: bool = await _until(func() -> bool: return house.visible)
	_check(opened, "an auctioneer opens the auction house")
	if not opened:
		await _teleport(HOME)
		return _finish("the auction house never opened")

	house.show_tab(AuctionFrame.Tab.AUCTIONS)
	await _frames(20)
	var listed: PackedStringArray = []
	house.message_added.connect(func(text: String) -> void: listed.append(text))
	session.send_chat(WowSession.CHAT_SAY, ".additem %d 1" % LINEN_CLOTH)
	var carried: bool = await _until(func() -> bool: return _first_of(LINEN_CLOTH).x >= 0)
	_check(carried, "the player carries something to sell")
	if not carried:
		await _teleport(HOME)
		return _finish("no item to auction")
	var stored: Vector2i = _first_of(LINEN_CLOTH)
	hud.use_container_item(stored.x, stored.y)
	await _frames(10)
	(house.find_child("StartPriceCopper", true, false) as LineEdit).text = "50"
	(house.find_child("AuctionsCreateAuctionButton", true, false) as BaseButton).pressed.emit()
	var created: bool = await _until(func() -> bool: return not listed.is_empty())
	_check(created, "creating an auction is confirmed")
	if created:
		print("auction answer: ", listed[0])
		var mine: bool = await _until(func() -> bool: return _own_auctions(house) > 0)
		_check(mine, "the auction shows under my auctions")
		await _check_bidding(house)
		house.show_tab(AuctionFrame.Tab.AUCTIONS)
		await _until(func() -> bool: return _own_auctions(house) > 0)
		if mine:
			(house.find_child("AuctionsButton1", true, false) as BaseButton).pressed.emit()
			await _frames(5)
			listed.clear()
			var cancel: BaseButton = house.find_child("AuctionsCancelAuctionButton", true, false)
			cancel.pressed.emit()
			var cancelled: bool = await _until(func() -> bool: return not listed.is_empty())
			_check(cancelled, "cancelling an auction is confirmed")
	(house.find_child("AuctionFrameCloseButton", true, false) as BaseButton).pressed.emit()
	await _frames(10)
	_check(not house.visible, "the close button shuts the auction house")
	await _teleport(HOME)
	_finish("")


# The server refuses a bid on your own auction, and says so only when the price was worth reading.
func _check_bidding(house: AuctionFrame) -> void:
	var refused: PackedStringArray = []
	var listener: Callable = func(text: String) -> void: refused.append(text)
	house.error_raised.connect(listener)
	house.show_tab(AuctionFrame.Tab.BROWSE)
	var row: int = -1
	for attempt: int in 5:
		await _frames(60)
		row = _row_of(house, LINEN_CLOTH)
		if row >= 0:
			break
		house.search()
	_check(row >= 0, "the auction is on the browse list")
	if row < 0:
		house.error_raised.disconnect(listener)
		return
	var price: MoneyFrame = house.find_child("BrowseButton%dMoneyFrame" % (row + 1), true, false)
	_check(price != null and price.visible, "the row shows what it costs")
	(house.find_child("BrowseButton%d" % (row + 1), true, false) as BaseButton).pressed.emit()
	await _frames(5)
	(house.find_child("BrowseBidButton", true, false) as BaseButton).pressed.emit()
	var answered: bool = await _until(func() -> bool: return not refused.is_empty())
	house.error_raised.disconnect(listener)
	_check(answered, "bidding on your own auction is refused")
	if not answered:
		return
	print("bid answer: ", refused[0])
	_check(
		refused[0] == WowStrings.get_text("ERR_AUCTION_BID_OWN"),
		"and refused for the right reason, not a price the server could not read",
	)
	house.show_tab(AuctionFrame.Tab.BID)
	await _frames(20)
	_check(WowClient.session.get_state() == WowSession.STATE_IN_WORLD, "the bid tab lists safely")


func _row_of(house: AuctionFrame, entry: int) -> int:
	for i: int in mini(house._listings.size(), AuctionFrame.ROWS):
		if house._listings[i]["item_entry"] == entry:
			return i
	return -1


func _own_auctions(house: AuctionFrame) -> int:
	var shown: int = 0
	for i: int in AuctionFrame.ROWS:
		var row: Control = house.find_child("AuctionsButton%d" % (i + 1), true, false)
		shown += int(row != null and row.visible)
	return shown


func _first_of(entry: int) -> Vector2i:
	for bag: int in Inventory.BAG_COUNT + 1:
		for slot: int in Inventory.container_size(bag):
			var item: int = Inventory.container_item(bag, slot)
			if item != 0 and Inventory.entry(item) == entry:
				return Vector2i(bag, slot)
	return Vector2i(-1, -1)


func _nearest_auctioneer() -> int:
	await get_tree().create_timer(2.0).timeout
	var session: WowSession = WowClient.session
	var here: Vector3 = session.get_object_position(session.get_player_guid())
	var best: int = 0
	var best_range: float = INF
	for guid: int in session.get_object_guids():
		if not session.get_field(guid, "UNIT_NPC_FLAGS") & NPC_FLAG_AUCTIONEER:
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
	await get_tree().create_timer(1.0).timeout
	var loaded_by: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while not _main.world.player().active and Time.get_ticks_msec() < loaded_by:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout


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
	print("auction_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
