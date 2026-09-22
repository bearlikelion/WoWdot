@tool
class_name TradeFrame
extends Control

signal open_requested
signal close_requested
signal trade_offered(player_name: String, player_guid: int)
signal message_added(text: String)
signal error_raised(text: String)

# SMSG_TRADE_STATUS, as TradeStatus names them.
enum Status { BUSY, BEGIN, OPEN_WINDOW, CANCELLED, ACCEPT, UNUSED, NO_TARGET, BACK_TO_TRADE,
	COMPLETE, REJECTED, TOO_FAR, WRONG_FACTION, CLOSE_WINDOW, UNUSED_13, IGNORING, YOU_STUNNED,
	TARGET_STUNNED, YOU_DEAD, TARGET_DEAD, YOU_LOGOUT, TARGET_LOGOUT }

# Six tradeable slots and the seventh, which only takes an item to enchant.
const SLOTS: int = 7
const TRADEABLE_SLOTS: int = 6
const STATUS_MESSAGES: Dictionary[Status, String] = {
	Status.BUSY: "ERR_TRADE_BUSY", Status.CANCELLED: "ERR_TRADE_CANCELLED",
	Status.NO_TARGET: "ERR_TRADE_TARGET_DEAD", Status.TOO_FAR: "ERR_TRADE_TOO_FAR",
	Status.WRONG_FACTION: "ERR_TRADE_WRONG_REALM", Status.IGNORING: "ERR_IGNORING_YOU_S",
	Status.YOU_DEAD: "ERR_TRADE_YOU_DEAD", Status.TARGET_DEAD: "ERR_TRADE_TARGET_DEAD",
}

var _partner: int = 0
# The player a trade was asked of or offered by, until the window opens.
var _pending: int = 0
var _mine: Array[int] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_mine.resize(SLOTS)
	for i: int in SLOTS:
		var slot: BaseButton = get_node("%%TradePlayerItem%dItemButton" % (i + 1))
		slot.pressed.connect(_clear_slot.bind(i))
	%TradeFrameTradeButton.pressed.connect(_accept)
	%TradeFrameCancelButton.pressed.connect(cancel)
	%TradeFrameCloseButton.pressed.connect(cancel)
	var session: WowSession = WowClient.session
	session.packet_received.connect(_on_packet_received)
	session.item_info_received.connect(func(_entry: int) -> void: _show_mine())
	hide()


func partner() -> int:
	return _partner


# CMSG_INITIATE_TRADE: asks the unit under the cursor to trade.
func start(guid: int) -> void:
	_pending = guid
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, guid)
	WowClient.session.send_packet("CMSG_INITIATE_TRADE", payload)


func accept_offer() -> void:
	WowClient.session.send_packet("CMSG_BEGIN_TRADE", PackedByteArray())


func decline_offer() -> void:
	cancel()


func cancel() -> void:
	WowClient.session.send_packet("CMSG_CANCEL_TRADE", PackedByteArray())
	_close()


# Right-clicking a bag item while a trade is open puts it in the first free slot.
func offer(bag: int, slot: int) -> bool:
	if not visible:
		return false
	var free: int = _mine.find(0)
	if free < 0 or free >= TRADEABLE_SLOTS:
		error_raised.emit(WowStrings.get_text("ERR_TRADE_MAX_COUNT_EXCEEDED", ""))
		return true
	var address: Vector2i = Inventory.wire_address(bag, slot)
	WowClient.session.send_packet(
		"CMSG_SET_TRADE_ITEM", PackedByteArray([free, address.x, address.y])
	)
	_mine[free] = Inventory.container_item(bag, slot)
	_show_mine()
	return true


func set_money(copper: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_u32(0, copper)
	WowClient.session.send_packet("CMSG_SET_TRADE_GOLD", payload)


func _accept() -> void:
	set_money(_typed_money())
	WowClient.session.send_packet("CMSG_ACCEPT_TRADE", PackedByteArray())


func _clear_slot(index: int) -> void:
	if _mine[index] == 0:
		return
	WowClient.session.send_packet("CMSG_CLEAR_TRADE_ITEM", PackedByteArray([index]))
	_mine[index] = 0
	_show_mine()


func _typed_money() -> int:
	var gold: int = (%TradePlayerInputMoneyFrameGold as LineEdit).text.to_int()
	var silver: int = (%TradePlayerInputMoneyFrameSilver as LineEdit).text.to_int()
	var copper: int = (%TradePlayerInputMoneyFrameCopper as LineEdit).text.to_int()
	return gold * MoneyFrame.COPPER_PER_GOLD + silver * MoneyFrame.COPPER_PER_SILVER + copper


func _show_mine() -> void:
	for i: int in SLOTS:
		_show_slot("TradePlayerItem%d" % (i + 1), Inventory.entry(_mine[i]))


func _show_slot(prefix: String, entry: int) -> void:
	var button: TextureButton = get_node("%%%sItemButton" % prefix)
	button.texture_normal = Inventory.icon(entry) if entry != 0 else null
	(get_node("%%%sName" % prefix) as Label).text = \
		WowClient.session.get_item_info(entry).get("name", "") if entry != 0 else ""


func _open(partner_guid: int) -> void:
	_partner = partner_guid
	_mine.fill(0)
	_show_mine()
	for i: int in SLOTS:
		_show_slot("TradeRecipientItem%d" % (i + 1), 0)
	%TradeFrameRecipientNameText.text = WowClient.session.get_object_name(partner_guid)
	open_requested.emit()


func _close() -> void:
	_partner = 0
	_mine.fill(0)
	close_requested.emit()


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	if opcode == "SMSG_TRADE_STATUS_EXTENDED":
		_read_offer(reader)
		return
	if opcode != "SMSG_TRADE_STATUS":
		return
	var status: Status = reader.u32() as Status
	match status:
		Status.BEGIN:
			_pending = reader.u64()
			trade_offered.emit(WowClient.session.get_object_name(_pending), _pending)
		Status.OPEN_WINDOW:
			_open(_pending)
		Status.COMPLETE:
			message_added.emit(WowStrings.get_text("ERR_TRADE_COMPLETE", "Trade complete."))
			_close()
		Status.CANCELLED, Status.CLOSE_WINDOW, Status.REJECTED:
			_close()
	var key: String = STATUS_MESSAGES.get(status, "")
	if not key.is_empty():
		error_raised.emit(WowStrings.get_text(key, ""))


# The other side's window: its money, then a fixed block for every slot, empty or not.
func _read_offer(reader: PacketReader) -> void:
	var theirs: bool = reader.u8() == 1
	if PacketReader.wotlk:
		reader.u32()
	reader.u32()
	reader.u32()
	var money: int = reader.u32()
	reader.u32()
	if not theirs:
		return
	(%TradeRecipientMoneyFrame as MoneyFrame).set_money(money)
	for i: int in SLOTS:
		var slot: int = reader.u8()
		var entry: int = reader.u32()
		reader.u32()
		reader.u32()
		reader.u32()
		reader.u64()
		reader.u32()
		if PacketReader.wotlk:
			for socket: int in 3:
				reader.u32()
		reader.u64()
		for skipped: int in 6:
			reader.u32()
		if slot < SLOTS:
			_show_slot("TradeRecipientItem%d" % (slot + 1), entry)
