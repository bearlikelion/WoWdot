@tool
class_name GuildRegistrarFrame
extends Control

signal open_requested
signal close_requested
signal error_raised(text: String)
signal message_added(text: String)

# The guild charter's item entry, which the server names in SMSG_PETITION_SHOWLIST as well.
const CHARTER_ENTRY: int = 5863
# SMSG_TURN_IN_PETITION_RESULTS and SMSG_PETITION_SIGN_RESULTS share these.
enum Sign { OK, ALREADY_SIGNED, ALREADY_IN_GUILD, CANT_SIGN_OWN, NEED_MORE }
const SIGN_ERRORS: Dictionary[Sign, String] = {
	Sign.ALREADY_SIGNED: "ERR_PETITION_ALREADY_SIGNED",
	Sign.ALREADY_IN_GUILD: "ERR_PETITION_IN_GUILD",
	Sign.CANT_SIGN_OWN: "ERR_PETITION_CREATOR",
	Sign.NEED_MORE: "ERR_PETITION_NOT_ENOUGH_SIGNATURES",
}

var _guid: int = 0
var _cost: int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	%GuildRegistrarButton1.pressed.connect(_show_purchase)
	%GuildRegistrarButton2.pressed.connect(_turn_in)
	%GuildRegistrarFramePurchaseButton.pressed.connect(_buy)
	%GuildRegistrarFrameCancelButton.pressed.connect(_show_greeting)
	%GuildRegistrarFrameGoodbyeButton.pressed.connect(close_requested.emit)
	%GuildRegistrarFrameCloseButton.pressed.connect(close_requested.emit)
	WowClient.session.packet_received.connect(_on_packet_received)
	hide()


# CMSG_PETITION_SHOWLIST: the gossip option already asks for this, so this is for a direct click.
func activate(guid: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, guid)
	WowClient.session.send_packet("CMSG_PETITION_SHOWLIST", payload)


func registrar() -> int:
	return _guid


# The charter in the player's bags, or 0 when none is carried.
func carried_charter() -> int:
	var found: Vector2i = Inventory.find_item(CHARTER_ENTRY)
	return Inventory.item_at(Inventory.wire_address(found.x, found.y)) if found.x >= 0 else 0


func _show_greeting() -> void:
	%GuildRegistrarGreetingFrame.show()
	%GuildRegistrarPurchaseFrame.hide()


func _show_purchase() -> void:
	%GuildRegistrarGreetingFrame.hide()
	%GuildRegistrarPurchaseFrame.show()
	(%GuildRegistrarMoneyFrame as MoneyFrame).set_money(_cost)


# CMSG_PETITION_BUY: the npc, the guild's name, and the slots a later client filled in.
func _buy() -> void:
	var wanted: String = (%GuildRegistrarFrameEditBox as LineEdit).text.strip_edges()
	if wanted.is_empty():
		error_raised.emit(WowStrings.get_text("ERR_GUILD_NAME_INVALID"))
		return
	var payload: PackedByteArray = []
	payload.resize(20)
	payload.encode_u64(0, _guid)
	var name_bytes: PackedByteArray = wanted.to_utf8_buffer()
	name_bytes.append(0)
	payload.append_array(name_bytes)
	var tail: PackedByteArray = []
	tail.resize(51)
	tail.encode_u32(43, 1)
	payload.append_array(tail)
	WowClient.session.send_packet("CMSG_PETITION_BUY", payload)


func _turn_in() -> void:
	var charter: int = carried_charter()
	if charter == 0:
		error_raised.emit(WowStrings.get_text("ERR_PETITION_NOT_ENOUGH_SIGNATURES"))
		return
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, charter)
	WowClient.session.send_packet("CMSG_TURN_IN_PETITION", payload)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_PETITION_SHOWLIST":
			_guid = reader.u64()
			_read_charters(reader)
			(%GuildRegistrarFrameNpcNameText as Label).text = \
				WowClient.session.get_object_name(_guid)
			_show_greeting()
			open_requested.emit()
		"SMSG_TURN_IN_PETITION_RESULTS":
			_on_turn_in_result(reader.u32() as Sign)


# Only the guild charter is offered in 1.12, and the server sends its cost with it.
func _read_charters(reader: PacketReader) -> void:
	for i: int in reader.u8():
		reader.u32()
		var entry: int = reader.u32()
		reader.u32()
		var cost: int = reader.u32()
		reader.u32()
		reader.u32()
		if entry == CHARTER_ENTRY:
			_cost = cost


func _on_turn_in_result(result: Sign) -> void:
	if result == Sign.OK:
		message_added.emit(WowStrings.get_text("ERR_PETITION_SIGNED"))
		return
	error_raised.emit(WowStrings.get_text(SIGN_ERRORS.get(result, "ERR_GUILD_INTERNAL")))
