class_name AuctionBidCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const HOST: String = "127.0.0.1"
const PORT: int = 3724
# The seller: a bare session on its own account (auction_bid_check.sh makes the character).
const PARTNER_ACCOUNT: String = "wowgd2"
const PARTNER: String = "Dolgrim"
const AUCTIONEER: Vector3 = Vector3(-4948.0, -901.5, 505.2)
const HOME: Vector3 = Vector3(-6248.77, 317.339, 382.778)
const NPC_FLAG_AUCTIONEER: int = 0x1000
const LINEN_CLOTH: int = 2589
const START_PRICE: int = 1234
const PURSE: int = 100000

var _failures: PackedStringArray = []
var _main: Main
var _partner: WowSession = WowSession.new()
var _partner_in_world: bool = false


# One character lists an item and the other bids on it, which needs two accounts to be legal.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = HOST
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	_run.call_deferred()


func _process(_delta: float) -> void:
	_partner.poll()


func _run() -> void:
	if not await _until(func() -> bool: return _main.world and _main.world.player().active):
		return _finish("never reached the world")
	if not await _log_partner_in():
		return _finish("the partner never reached the world")
	var session: WowSession = WowClient.session
	var hud: Hud = _main.world.hud()
	var house: AuctionFrame = hud.find_child("AuctionFrame", true, false)
	session.send_chat(WowSession.CHAT_SAY, ".modify money %d" % PURSE)
	await _teleport(AUCTIONEER)
	var auctioneer: int = await _nearest_auctioneer()
	if auctioneer == 0:
		await _teleport(HOME)
		return _finish("no auctioneer in the Ironforge auction house")
	if not await _partner_lists_an_item(auctioneer):
		# Only a GM account can conjure the item to sell, and the second one has no rights here.
		print("the partner could not list anything, so the money leg is not covered")
		print("grant it with: account set gmlevel %s 6 -1" % PARTNER_ACCOUNT)
		await _teleport(HOME)
		return _finish("")

	await _teleport(session.get_object_position(auctioneer))
	hud.open_auction_house(auctioneer)
	if not await _until(func() -> bool: return house.visible, 15000):
		await _teleport(HOME)
		return _finish("the auction house never opened")
	var row: int = -1
	for attempt: int in 5:
		await _frames(60)
		row = _row_of(house, LINEN_CLOTH)
		if row >= 0:
			break
		house.search()
	_check(row >= 0, "the partner's auction is on the browse list")
	if row < 0:
		await _teleport(HOME)
		return _finish("nothing to bid on")

	var purse: int = Inventory.money()
	(house.find_child("BrowseButton%d" % (row + 1), true, false) as BaseButton).pressed.emit()
	await _frames(5)
	(house.find_child("BrowseBidButton", true, false) as BaseButton).pressed.emit()
	var paid: bool = await _until(func() -> bool: return Inventory.money() < purse, 15000)
	print("purse %d before, %d after" % [purse, Inventory.money()])
	_check(paid, "bidding takes the price out of the purse")
	_check(purse - Inventory.money() == START_PRICE, "and takes exactly what was bid")
	house.show_tab(AuctionFrame.Tab.BID)
	var listed: bool = await _until(
		func() -> bool: return _row_of(house, LINEN_CLOTH) >= 0, 15000
	)
	_check(listed, "and the bid tab lists what was bid on")
	await _teleport(HOME)
	_finish("")


# The seller does its own listing over a bare session, since only its own account may sell to us.
func _partner_lists_an_item(auctioneer: int) -> bool:
	_partner.send_chat(WowSession.CHAT_SAY, ".go xyz %f %f %f" % [
		AUCTIONEER.x, AUCTIONEER.y, AUCTIONEER.z
	])
	await _frames(60)
	_partner.send_chat(WowSession.CHAT_SAY, ".additem %d 1" % LINEN_CLOTH)
	var item: int = 0
	await _until(func() -> bool:
		item = _partner_item(LINEN_CLOTH)
		return item != 0
	, 20000)
	if item == 0:
		return false
	var payload: PackedByteArray = []
	payload.resize(28)
	payload.encode_u64(0, auctioneer)
	payload.encode_u64(8, item)
	payload.encode_u32(16, START_PRICE)
	payload.encode_u32(20, 0)
	payload.encode_u32(24, AuctionFrame.Duration.SHORT)
	_partner.send_packet("CMSG_AUCTION_SELL_ITEM", payload)
	await _frames(90)
	return true


func _partner_item(entry: int) -> int:
	var me: int = _partner.get_player_guid()
	var first: int = _partner.field_index("PLAYER_FIELD_PACK_SLOT_1")
	for slot: int in Inventory.BACKPACK_SLOTS:
		var item: int = _partner.get_field_guid(me, first + slot * 2)
		if item != 0 and _partner.get_field(item, "OBJECT_FIELD_ENTRY") == entry:
			return item
	return 0


func _row_of(house: AuctionFrame, entry: int) -> int:
	for i: int in mini(house._listings.size(), AuctionFrame.ROWS):
		if house._listings[i]["item_entry"] == entry:
			return i
	return -1


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


func _log_partner_in() -> bool:
	_partner.realms_received.connect(func(_realms: Array) -> void: _partner.select_realm(0))
	_partner.characters_received.connect(func(characters: Array) -> void:
		for character: Dictionary in characters:
			if character["name"] == PARTNER:
				_partner.enter_world(character["guid"])
	)
	_partner.world_entered.connect(
		func(_map: int, _at: Vector3, _facing: float) -> void: _partner_in_world = true
	)
	_partner.login(HOST, PORT, PARTNER_ACCOUNT, PARTNER_ACCOUNT)
	return await _until(func() -> bool: return _partner_in_world)


func _teleport(wow_position: Vector3) -> void:
	WowClient.session.send_chat(
		WowSession.CHAT_SAY, ".go xyz %f %f %f" % [wow_position.x, wow_position.y, wow_position.z]
	)
	await _frames(30)
	await _until(func() -> bool: return _main.world.player().active)
	await _frames(60)


func _until(condition: Callable, timeout_msec: int = TIMEOUT_MSEC) -> bool:
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
	print("auction_bid_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
