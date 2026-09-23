@tool
class_name AuctionFrame
extends Control

signal open_requested
signal close_requested
signal error_raised(text: String)
signal message_added(text: String)

enum Tab { BROWSE, BID, AUCTIONS }
# Auction durations in minutes, as the stock radio buttons offer them.
enum Duration { SHORT = 120, MEDIUM = 480, LONG = 1440 }

const ROWS: int = 8
const TAB_OVERLAP: float = -8.0
const AUCTION_OK: int = 0
const NO_FILTER: int = 0xFFFFFFFF
# SMSG_AUCTION_COMMAND_RESULT actions.
const ACTION_SOLD: int = 0
const ACTION_CANCELLED: int = 1
const ACTION_BID_PLACED: int = 2
# Its error codes, by the global string that names each one.
const AUCTION_ERRORS: Dictionary[int, String] = {
	1: "ERR_INVENTORY_FULL", 2: "ERR_AUCTION_DATABASE_ERROR", 3: "ERR_NOT_ENOUGH_MONEY",
	4: "ERR_ITEM_NOT_FOUND", 5: "ERR_AUCTION_HIGHER_BID", 7: "ERR_AUCTION_BID_INCREMENT",
	10: "ERR_AUCTION_BID_OWN", 13: "ERR_AUCTION_DATABASE_ERROR",
}
const ERROR_HIGHER_BID: int = 5
const ERROR_INVENTORY: int = 1
# AzerothCore only accepts 12, 24 or 48 hour auctions.
const WOTLK_MINUTES: Dictionary[Duration, int] = {
	Duration.SHORT: 720, Duration.MEDIUM: 1440, Duration.LONG: 2880,
}
# Each tab names its rows and its current bid frame differently.
const ROW_PREFIX: Dictionary[Tab, String] = {
	Tab.BROWSE: "Browse", Tab.BID: "Bid", Tab.AUCTIONS: "Auctions",
}
const BID_FRAME: Dictionary[Tab, String] = {
	Tab.BROWSE: "MoneyFrame", Tab.BID: "CurrentBidMoneyFrame", Tab.AUCTIONS: "MoneyFrame",
}

var _guid: int = 0
var _tab: Tab = Tab.BROWSE
var _listings: Array[Dictionary] = []
var _selling: int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for i: int in ROWS:
		for prefix: String in ROW_PREFIX.values():
			var row: BaseButton = get_node("%%%sButton%d" % [prefix, i + 1])
			row.pressed.connect(_on_row_pressed.bind(i))
	%AuctionFrameCloseButton.pressed.connect(close_requested.emit)
	%AuctionFrameTab1.pressed.connect(show_tab.bind(Tab.BROWSE))
	%AuctionFrameTab2.pressed.connect(show_tab.bind(Tab.BID))
	%AuctionFrameTab3.pressed.connect(show_tab.bind(Tab.AUCTIONS))
	PanelManager.chain_tabs([%AuctionFrameTab1, %AuctionFrameTab2, %AuctionFrameTab3], TAB_OVERLAP)
	%BrowseSearchButton.pressed.connect(search)
	%BrowseBidButton.pressed.connect(_bid)
	%BrowseBuyoutButton.pressed.connect(_buyout)
	%BidBidButton.pressed.connect(_bid)
	%AuctionsCancelAuctionButton.pressed.connect(_cancel)
	%AuctionsCreateAuctionButton.pressed.connect(_create)
	WowClient.session.packet_received.connect(_on_packet_received)
	hide()


func auctioneer() -> int:
	return _guid


# MSG_AUCTION_HELLO: right-clicking an auctioneer opens the house they work for.
func hello(guid: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, guid)
	WowClient.session.send_packet("MSG_AUCTION_HELLO", payload)


# Right-clicking a bag item while the house is open puts it up for sale.
func offer(item: int) -> bool:
	if _guid == 0 or _tab != Tab.AUCTIONS:
		return false
	_selling = item
	_show_offer()
	return true


func show_tab(tab: Tab) -> void:
	_tab = tab
	%AuctionFrameBrowse.visible = tab == Tab.BROWSE
	%AuctionFrameBid.visible = tab == Tab.BID
	%AuctionFrameAuctions.visible = tab == Tab.AUCTIONS
	_refresh_tab()


# The server drops a list request while another is still in flight, so only one goes out at a time.
func _refresh_tab() -> void:
	match _tab:
		Tab.BROWSE:
			search()
		Tab.BID:
			_list_bids()
		Tab.AUCTIONS:
			_list_own()


# CMSG_AUCTION_LIST_ITEMS: the search box and no filters, which lists everything on sale.
func search() -> void:
	var payload: PackedByteArray = []
	payload.resize(12)
	payload.encode_u64(0, _guid)
	payload.encode_u32(8, 0)
	var wanted: PackedByteArray = (%BrowseName as LineEdit).text.to_utf8_buffer()
	wanted.append(0)
	payload.append_array(wanted)
	var filters: PackedByteArray = []
	filters.resize(19)
	filters.encode_u8(0, 0)
	filters.encode_u8(1, 0)
	# Slot, class, subclass and quality unset are 0xFFFFFFFF; zero would filter to item class 0.
	for offset: int in [2, 6, 10, 14]:
		filters.encode_u32(offset, NO_FILTER)
	filters.encode_u8(18, 0)
	payload.append_array(filters)
	if PacketReader.wotlk:
		# getAll off and no sort columns.
		payload.append_array(PackedByteArray([0, 0]))
	WowClient.session.send_packet("CMSG_AUCTION_LIST_ITEMS", payload)


func refresh() -> void:
	var prefix: String = ROW_PREFIX[_tab]
	for i: int in ROWS:
		var listing: Dictionary = _listings[i] if i < _listings.size() else {}
		var row: Control = get_node("%%%sButton%d" % [prefix, i + 1])
		row.visible = not listing.is_empty()
		if listing.is_empty():
			continue
		var entry: int = listing["item_entry"]
		var name_label: Label = get_node_or_null("%%%sButton%dName" % [prefix, i + 1])
		if name_label:
			name_label.text = WowClient.session.get_item_info(entry).get("name", "")
		(get_node("%%%sButton%dItemIconTexture" % [prefix, i + 1]) as TextureRect).texture = \
			Inventory.icon(entry)
		_set_row_money(prefix, i, BID_FRAME[_tab], listing["bid"])
		_set_row_money(prefix, i, "BuyoutMoneyFrame", listing["buyout"])
		var bidder: Label = get_node_or_null("%%%sButton%dHighBidder" % [prefix, i + 1])
		if bidder:
			bidder.text = WowClient.session.get_object_name(listing["bidder"]) \
			if listing["bidder"] != 0 else ""
	(%BrowseSearchCountText as Label).text = str(_listings.size())


# A row with no bid on it shows the starting price, as the stock list does.
func _set_row_money(prefix: String, row: int, frame_name: String, copper: int) -> void:
	var frame: MoneyFrame = get_node_or_null("%%%sButton%d%s" % [prefix, row + 1, frame_name])
	if frame:
		frame.set_money(copper)


# The stock slot shows the item as the button's own art, with its name under it.
func _show_offer() -> void:
	var entry: int = Inventory.entry(_selling)
	var button: TextureButton = %AuctionsItemButton
	button.texture_normal = Inventory.icon(entry) if entry != 0 else null
	(%AuctionsItemButtonName as Label).text = \
		WowClient.session.get_item_info(entry).get("name", "") if entry != 0 else ""


func _selected() -> Dictionary:
	var index: int = (%BrowseScrollFrame as WowScrollFrame).get_meta(&"selected", -1) \
	if %BrowseScrollFrame.has_meta(&"selected") else -1
	return _listings[index] if index >= 0 and index < _listings.size() else {}


func _on_row_pressed(index: int) -> void:
	%BrowseScrollFrame.set_meta(&"selected", index)


# AuctionFrameBid_OnClick: the first bid is the starting price, later ones clear the increment.
func _bid() -> void:
	var listing: Dictionary = _selected()
	if listing.is_empty():
		return
	var price: int = listing["start_bid"] if listing["bid"] == 0 \
	else listing["bid"] + listing["increment"]
	_place_bid(listing["id"], price)


func _buyout() -> void:
	var listing: Dictionary = _selected()
	if not listing.is_empty() and listing["buyout"] > 0:
		_place_bid(listing["id"], listing["buyout"])


func _place_bid(auction_id: int, price: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(16)
	payload.encode_u64(0, _guid)
	payload.encode_u32(8, auction_id)
	payload.encode_u32(12, price)
	WowClient.session.send_packet("CMSG_AUCTION_PLACE_BID", payload)


func _cancel() -> void:
	var listing: Dictionary = _selected()
	if listing.is_empty():
		return
	var payload: PackedByteArray = []
	payload.resize(12)
	payload.encode_u64(0, _guid)
	payload.encode_u32(8, listing["id"])
	WowClient.session.send_packet("CMSG_AUCTION_REMOVE_ITEM", payload)


# CMSG_AUCTION_SELL_ITEM: the item on the slot, its starting bid, its buyout and how long it runs.
func _create() -> void:
	if _selling == 0:
		error_raised.emit(WowStrings.get_text("ERR_AUCTION_STARTED", ""))
		return
	var payload: PackedByteArray = []
	payload.resize(28)
	payload.encode_u64(0, _guid)
	payload.encode_u64(8, _selling)
	payload.encode_u32(16, _typed_money("StartPrice"))
	payload.encode_u32(20, _typed_money("BuyoutPrice"))
	payload.encode_u32(24, Duration.SHORT)
	if PacketReader.wotlk:
		# One item with its whole stack.
		payload.resize(40)
		payload.encode_u32(8, 1)
		payload.encode_u64(12, _selling)
		payload.encode_u32(20, Inventory.stack_count(_selling))
		payload.encode_u32(24, _typed_money("StartPrice"))
		payload.encode_u32(28, _typed_money("BuyoutPrice"))
		payload.encode_u32(32, WOTLK_MINUTES[Duration.SHORT])
	WowClient.session.send_packet("CMSG_AUCTION_SELL_ITEM", payload)


func _typed_money(box: String) -> int:
	var gold: int = (get_node("%%%sGold" % box) as LineEdit).text.to_int()
	var silver: int = (get_node("%%%sSilver" % box) as LineEdit).text.to_int()
	var copper: int = (get_node("%%%sCopper" % box) as LineEdit).text.to_int()
	return gold * MoneyFrame.COPPER_PER_GOLD + silver * MoneyFrame.COPPER_PER_SILVER + copper


# CMSG_AUCTION_LIST_BIDDER_ITEMS with no ids listed asks for everything the player has bid on.
func _list_bids() -> void:
	var payload: PackedByteArray = []
	payload.resize(16)
	payload.encode_u64(0, _guid)
	payload.encode_u32(8, 0)
	payload.encode_u32(12, 0)
	WowClient.session.send_packet("CMSG_AUCTION_LIST_BIDDER_ITEMS", payload)


func _list_own() -> void:
	var payload: PackedByteArray = []
	payload.resize(12)
	payload.encode_u64(0, _guid)
	payload.encode_u32(8, 0)
	WowClient.session.send_packet("CMSG_AUCTION_LIST_OWNER_ITEMS", payload)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"MSG_AUCTION_HELLO":
			_guid = reader.u64()
			show_tab(Tab.BROWSE)
			open_requested.emit()
		"SMSG_AUCTION_LIST_RESULT", "SMSG_AUCTION_OWNER_LIST_RESULT", \
		"SMSG_AUCTION_BIDDER_LIST_RESULT":
			_listings = _read_listings(reader)
			refresh()
		"SMSG_AUCTION_COMMAND_RESULT":
			_on_command_result(reader)


func _on_command_result(reader: PacketReader) -> void:
	reader.u32()
	var action: int = reader.u32()
	var result: int = reader.u32()
	if result != AUCTION_OK:
		var key: String = AUCTION_ERRORS.get(result, "ERR_AUCTION_DATABASE_ERROR")
		error_raised.emit(WowStrings.get_text(key, ""))
		return
	if action == ACTION_SOLD:
		_selling = 0
		_show_offer()
		message_added.emit(WowStrings.get_text("ERR_AUCTION_STARTED", "Auction created."))
	elif action == ACTION_CANCELLED:
		message_added.emit(WowStrings.get_text("ERR_AUCTION_REMOVED", "Auction cancelled."))
	elif action == ACTION_BID_PLACED:
		message_added.emit(WowStrings.get_text("ERR_AUCTION_BID_PLACED", "Bid accepted."))
	_refresh_tab()


func _read_listings(reader: PacketReader) -> Array[Dictionary]:
	var listings: Array[Dictionary] = []
	for i: int in reader.u32():
		var listing: Dictionary = {"id": reader.u32(), "item_entry": reader.u32()}
		# 3.3.5 lists seven enchantment triples where 1.12 had one enchantment.
		for skipped: int in 23 if PacketReader.wotlk else 3:
			reader.u32()
		listing["count"] = reader.u32()
		for skipped: int in 2 if PacketReader.wotlk else 1:
			reader.u32()
		listing["owner"] = reader.u64()
		listing["start_bid"] = reader.u32()
		listing["increment"] = reader.u32()
		listing["buyout"] = reader.u32()
		listing["time_left_msec"] = reader.u32()
		listing["bidder"] = reader.u64()
		listing["bid"] = reader.u32()
		listings.append(listing)
	return listings
