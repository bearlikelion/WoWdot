class_name GuildBank
extends RefCounted

signal opened
signal changed

const MAX_TABS: int = 6
const SLOTS: int = 98
# GuildEvents GE_BANK_TAB_PURCHASED to GE_BANK_TAB_AND_MONEY_UPDATED, after which the list is stale.
const BANK_EVENTS: Array[int] = [15, 16, 17, 18]

# The vault in use, which every bank packet names.
var banker: int = 0
var money: int = 0
var withdrawals_remaining: int = 0
# Each bought tab as {name, icon}.
var tabs: Array[Dictionary] = []
# Tab index to its slots, each {item, count} or {} when empty.
var items: Dictionary[int, Array] = {}

var _session: WowSession


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)


func activate(vault: int) -> void:
	banker = vault
	items.clear()
	_send("CMSG_GUILD_BANKER_ACTIVATE", PackedByteArray([1]))
	opened.emit()


func query_tab(tab: int) -> void:
	_send("CMSG_GUILD_BANK_QUERY_TAB", PackedByteArray([tab, 1]))


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
