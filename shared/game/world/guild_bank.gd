class_name GuildBank
extends RefCounted

signal opened
signal changed
signal log_received(tab: int)
signal text_received(tab: int)

# GuildBankEventLogTypes.
enum LogType {
	DEPOSIT_ITEM = 1, WITHDRAW_ITEM, MOVE_ITEM, DEPOSIT_MONEY, WITHDRAW_MONEY, REPAIR_MONEY,
	MOVE_ITEM2, WITHDRAW_FOR_TAB, BUY_SLOT,
}

const MAX_TABS: int = 6
const SLOTS: int = 98
# GuildEvents GE_BANK_TAB_PURCHASED to GE_BANK_TAB_AND_MONEY_UPDATED, after which the list is stale.
const BANK_EVENTS: Array[int] = [15, 16, 17, 18]
# QueryGuildBankLog(MAX_GUILDBANK_TABS + 1) asks for the money log, which the wire numbers 6.
const MONEY_LOG: int = MAX_TABS

# The vault in use, which every bank packet names.
var banker: int = 0
var money: int = 0
var withdrawals_remaining: int = 0
# Copper the player may still take out today, or -1 for no limit.
var money_remaining: int = -1
# Each bought tab as {name, icon}.
var tabs: Array[Dictionary] = []
# Tab index to its slots, each {item, count} or {} when empty.
var items: Dictionary[int, Array] = {}
# Tab, or MONEY_LOG, to its entries oldest first: {type, player, item, count, tab, money, seconds}.
var logs: Dictionary[int, Array] = {}
var texts: Dictionary[int, String] = {}

var _session: WowSession


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)


func activate(vault: int) -> void:
	banker = vault
	items.clear()
	_send("CMSG_GUILD_BANKER_ACTIVATE", PackedByteArray([1]))
	_session.send_packet("MSG_GUILD_BANK_MONEY_WITHDRAWN", PackedByteArray())
	opened.emit()


func query_tab(tab: int) -> void:
	_send("CMSG_GUILD_BANK_QUERY_TAB", PackedByteArray([tab, 1]))


func query_log(tab: int) -> void:
	_session.send_packet("MSG_GUILD_BANK_LOG_QUERY", PackedByteArray([tab]))


func query_text(tab: int) -> void:
	_session.send_packet("MSG_QUERY_GUILD_BANK_TEXT", PackedByteArray([tab]))


func set_text(tab: int, text: String) -> void:
	var payload: PackedByteArray = [tab]
	payload.append_array(text.to_utf8_buffer())
	payload.append(0)
	_session.send_packet("CMSG_SET_GUILD_BANK_TEXT", payload)
	texts[tab] = text


func buy_tab(tab: int) -> void:
	_send("CMSG_GUILD_BANK_BUY_TAB", PackedByteArray([tab]))


func deposit_money(copper: int) -> void:
	_send_money("CMSG_GUILD_BANK_DEPOSIT_MONEY", copper)


func withdraw_money(copper: int) -> void:
	_send_money("CMSG_GUILD_BANK_WITHDRAW_MONEY", copper)


# A whole stack from a wire bag and slot into a bank slot.
func deposit_item(tab: int, slot: int, from: Vector2i) -> void:
	var buffer: StreamPeerBuffer = _swap(tab, slot, 0)
	buffer.put_u8(0)
	buffer.put_u8(from.x)
	buffer.put_u8(from.y)
	# Towards the bank, and the whole stack.
	buffer.put_u8(0)
	buffer.put_32(0)
	_send("CMSG_GUILD_BANK_SWAP_ITEMS", buffer.data_array)


# A whole bank stack into the first free bag slot.
func withdraw_item(tab: int, slot: int) -> void:
	var stack: Dictionary = items.get(tab, [])[slot] if items.has(tab) else {}
	var buffer: StreamPeerBuffer = _swap(tab, slot, stack.get("item", 0))
	buffer.put_u8(1)
	buffer.put_32(0)
	buffer.put_u8(0)
	buffer.put_32(0)
	_send("CMSG_GUILD_BANK_SWAP_ITEMS", buffer.data_array)


func _swap(tab: int, slot: int, item: int) -> StreamPeerBuffer:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	# Between the bank and the player's bags rather than within the bank.
	buffer.put_u8(0)
	buffer.put_u8(tab)
	buffer.put_u8(slot)
	buffer.put_u32(item)
	return buffer


func _send_money(opcode: String, copper: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_u32(0, copper)
	_send(opcode, payload)


func _send(opcode: String, tail: PackedByteArray) -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, banker)
	payload.append_array(tail)
	_session.send_packet(opcode, payload)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	if opcode == "SMSG_GUILD_EVENT" and banker and reader.u8() in BANK_EVENTS:
		_send("CMSG_GUILD_BANKER_ACTIVATE", PackedByteArray([1]))
	if opcode == "MSG_GUILD_BANK_LOG_QUERY":
		_read_log(reader)
		return
	if opcode == "MSG_QUERY_GUILD_BANK_TEXT":
		var tab: int = reader.u8()
		texts[tab] = reader.cstring()
		text_received.emit(tab)
		return
	if opcode == "MSG_GUILD_BANK_MONEY_WITHDRAWN":
		money_remaining = reader.i32()
		changed.emit()
		return
	if opcode != "SMSG_GUILD_BANK_LIST":
		return
	money = reader.u64()
	var tab: int = reader.u8()
	withdrawals_remaining = reader.i32()
	var full: bool = reader.u8() != 0
	if tab == 0 and full:
		tabs.clear()
		for i: int in reader.u8():
			tabs.append({"name": reader.cstring(), "icon": reader.cstring()})
	var slots: Array = items.get(tab, [])
	if full or slots.is_empty():
		slots = []
		slots.resize(SLOTS)
		slots.fill({})
	for i: int in reader.u8():
		var slot: int = reader.u8()
		var item: int = reader.u32()
		var stack: Dictionary = {}
		if item:
			reader.skip(4)
			if reader.i32() != 0:
				reader.skip(4)
			stack = {"item": item, "count": reader.i32()}
			reader.skip(5)
			reader.skip(reader.u8() * 5)
		if slot < SLOTS:
			slots[slot] = stack
	items[tab] = slots
	changed.emit()


# The server sends the newest entry first.
func _read_log(reader: PacketReader) -> void:
	var tab: int = reader.u8()
	var entries: Array[Dictionary] = []
	for i: int in reader.u8():
		var entry: Dictionary = {"type": reader.u8(), "player": reader.u64()}
		match entry["type"]:
			LogType.DEPOSIT_ITEM, LogType.WITHDRAW_ITEM:
				entry["item"] = reader.u32()
				entry["count"] = reader.u32()
			LogType.MOVE_ITEM, LogType.MOVE_ITEM2:
				entry["item"] = reader.u32()
				entry["count"] = reader.u32()
				entry["tab"] = reader.u8()
			_:
				entry["money"] = reader.u32()
		entry["seconds"] = reader.u32()
		entries.push_front(entry)
	logs[tab] = entries
	log_received.emit(tab)
