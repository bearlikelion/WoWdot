@tool
class_name BankFrame
extends Control

signal open_requested
signal close_requested
signal error_raised(text: String)

# BANK_SLOT_ITEM_START, as the wire counts the player's own slots.
const BANK_SLOT_START: int = 39
const BANK_SLOTS: int = 24
const BANK_BAGS: int = 6
const OWN_BAG: int = 255
const BAG_SLOT_ICON: String = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag.blp"

var _guid: int = 0
var _bought_bags: int = 0
var _empty_bag_icon: WowTexture = WowTexture.new()

var _items: Array[ItemButton] = []
var _bags: Array[ItemButton] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_empty_bag_icon.file = BAG_SLOT_ICON
	for i: int in BANK_SLOTS:
		var button: ItemButton = get_node("%%BankFrameItem%d" % (i + 1))
		button.address = Vector2i(Inventory.WIRE_BACKPACK, Inventory.WIRE_BANK_SLOT_START + i)
		button.pressed.connect(_take_item.bind(i))
		button.right_clicked.connect(_take_item.bind(i))
		button.mouse_entered.connect(_show_tooltip.bind(button, _bank_item.bind(i)))
		button.mouse_exited.connect(_hide_tooltip.bind(button))
		_items.append(button)
	for i: int in BANK_BAGS:
		var bag: ItemButton = get_node("%%BankFrameBag%d" % (i + 1))
		bag.mouse_entered.connect(_show_tooltip.bind(bag, _bank_bag.bind(i)))
		bag.mouse_exited.connect(_hide_tooltip.bind(bag))
		_bags.append(bag)
	%BankCloseButton.pressed.connect(close_requested.emit)
	%BankFramePurchaseButton.pressed.connect(_buy_slot)
	var session: WowSession = WowClient.session
	session.packet_received.connect(_on_packet_received)
	session.object_updated.connect(_on_object_updated)
	hide()


# CMSG_BANKER_ACTIVATE: right-clicking a banker opens the bank without a gossip menu.
func activate(guid: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, guid)
	WowClient.session.send_packet("CMSG_BANKER_ACTIVATE", payload)


# The banker the player is talking to, or 0 when the bank is closed.
func banker() -> int:
	return _guid


# Right-clicking a bag item while the bank is open puts it away.
func store(bag: int, slot: int) -> bool:
	if _guid == 0:
		return false
	var address: Vector2i = Inventory.wire_address(bag, slot)
	WowClient.session.send_packet(
		"CMSG_AUTOBANK_ITEM", PackedByteArray([address.x, address.y])
	)
	return true


func refresh() -> void:
	for i: int in BANK_SLOTS:
		_show(_items[i], _bank_item(i))
	for i: int in BANK_BAGS:
		var bag: int = _bank_bag(i)
		_show(_bags[i], bag)
		if bag == 0:
			_bags[i].set_item(_empty_bag_icon)
		_bags[i].modulate.a = 1.0 if i < _bought_bags else 0.5
	var next_cost: int = _slot_cost(_bought_bags)
	%BankFramePurchaseInfo.visible = next_cost > 0
	(%BankFrameDetailMoneyFrame as MoneyFrame).set_money(next_cost)
	(%BankFrameMoneyFrame as MoneyFrame).set_money(Inventory.money())


func _show(button: ItemButton, item: int) -> void:
	var entry: int = Inventory.entry(item)
	button.set_item(Inventory.icon(entry) if entry != 0 else null, Inventory.stack_count(item))


# BankBagSlotPrices holds one row per bag slot, in the order they are bought.
func _slot_cost(bought: int) -> int:
	if bought >= BANK_BAGS:
		return 0
	var prices: WowDBC = WowDBC.open(WowAssets.archive, "BankBagSlotPrices")
	var row: int = prices.find(bought + 1)
	return prices.get_uint(row, 1) if row >= 0 else 0


func _bank_item(index: int) -> int:
	var session: WowSession = WowClient.session
	var first: int = session.field_index("PLAYER_FIELD_BANK_SLOT_1")
	return session.get_field_guid(session.get_player_guid(), first + index * 2)


func _bank_bag(index: int) -> int:
	var session: WowSession = WowClient.session
	var first: int = session.field_index("PLAYER_FIELD_BANKBAG_SLOT_1")
	return session.get_field_guid(session.get_player_guid(), first + index * 2)


func _take_item(index: int) -> void:
	if _bank_item(index) == 0:
		return
	WowClient.session.send_packet(
		"CMSG_AUTOSTORE_BANK_ITEM", PackedByteArray([OWN_BAG, BANK_SLOT_START + index])
	)


func _buy_slot() -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, _guid)
	WowClient.session.send_packet("CMSG_BUY_BANK_SLOT", payload)


func _show_tooltip(button: ItemButton, item: Callable) -> void:
	var guid: int = item.call()
	if GameTooltip.current and guid != 0:
		GameTooltip.current.set_item(button, Inventory.entry(guid), guid)


func _hide_tooltip(button: ItemButton) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(button)


func _on_object_updated(guid: int) -> void:
	if visible and guid == WowClient.session.get_player_guid():
		refresh()


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_SHOW_BANK":
			_guid = reader.u64()
			_bought_bags = _bought_bag_count()
			refresh()
			open_requested.emit()
		"SMSG_BUY_BANK_SLOT_RESULT":
			if reader.u32() != 0:
				error_raised.emit(WowStrings.get_text("ERR_BANKSLOT_FAILED_TOO_MANY", ""))
				return
			_bought_bags = _bought_bag_count()
			refresh()


# PLAYER_BYTES_2 byte 2 counts the bank bag slots the player has bought.
func _bought_bag_count() -> int:
	var session: WowSession = WowClient.session
	return (session.get_field(session.get_player_guid(), "PLAYER_BYTES_2") >> 16) & 0xFF
