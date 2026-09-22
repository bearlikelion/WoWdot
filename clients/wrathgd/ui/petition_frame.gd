@tool
class_name PetitionFrame
extends Control

signal open_requested
signal close_requested
signal error_raised(text: String)
signal message_added(text: String)

const SIGNATURES: int = 9

var _item: int = 0
var _petition: int = 0
var _owner: int = 0
var _title: String = ""
var _signers: PackedInt64Array = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	%PetitionFrameSignButton.pressed.connect(_sign)
	%PetitionFrameRequestButton.pressed.connect(_request)
	%PetitionFrameCancelButton.pressed.connect(close_requested.emit)
	%PetitionFrameCloseButton.pressed.connect(close_requested.emit)
	# Renaming needs a popup this client does not have, and the stock one hides it for signers.
	%PetitionFrameRenameButton.hide()
	WowClient.session.packet_received.connect(_on_packet_received)
	hide()


# CMSG_PETITION_SHOW_SIGNATURES: right-clicking a charter asks who has signed it.
func show_signatures(item: int) -> void:
	_item = item
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, item)
	WowClient.session.send_packet("CMSG_PETITION_SHOW_SIGNATURES", payload)


func charter_name() -> String:
	return _title


func signers() -> PackedInt64Array:
	return _signers


func _sign() -> void:
	var payload: PackedByteArray = []
	payload.resize(9)
	payload.encode_u64(0, _item)
	WowClient.session.send_packet("CMSG_PETITION_SIGN", payload)


# CMSG_OFFER_PETITION shows the charter to whoever is targeted, so they can sign it.
func _request() -> void:
	var session: WowSession = WowClient.session
	var target: int = session.get_field_guid(session.get_player_guid(), "UNIT_FIELD_TARGET")
	if target == 0:
		error_raised.emit(WowStrings.get_text("ERR_BADATTACKPOS"))
		return
	var payload: PackedByteArray = []
	var offset: int = 4 if PacketReader.wotlk else 0
	payload.resize(offset + 16)
	payload.encode_u64(offset, _item)
	payload.encode_u64(offset + 8, target)
	session.send_packet("CMSG_OFFER_PETITION", payload)
	message_added.emit(
		WowStrings.get_text("ERR_PETITION_OFFERED_S") % session.get_object_name(target)
	)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_PETITION_SHOW_SIGNATURES":
			_read_signatures(reader)
		"SMSG_PETITION_QUERY_RESPONSE":
			reader.u32()
			reader.u64()
			_title = reader.cstring()
			_refresh()
		"SMSG_PETITION_SIGN_RESULTS":
			reader.u64()
			reader.u64()
			_on_sign_result(reader.u32() as GuildRegistrarFrame.Sign)


func _read_signatures(reader: PacketReader) -> void:
	_item = reader.u64()
	_owner = reader.u64()
	_petition = reader.u32()
	_signers = PackedInt64Array()
	for i: int in reader.u8():
		_signers.append(reader.u64())
		reader.u32()
	_query_name()
	_refresh()
	open_requested.emit()


# CMSG_PETITION_QUERY: the signature list carries no title, so the name comes from its own query.
func _query_name() -> void:
	var payload: PackedByteArray = []
	payload.resize(12)
	payload.encode_u32(0, _petition)
	payload.encode_u64(4, _item)
	WowClient.session.send_packet("CMSG_PETITION_QUERY", payload)


# PetitionFrame_Update: the owner asks others to sign, everyone else signs.
func _refresh() -> void:
	var session: WowSession = WowClient.session
	var mine: bool = _owner == session.get_player_guid()
	(%PetitionFrameNpcNameText as Label).text = \
		WowStrings.get_text("GUILD_CHARTER_TEMPLATE") % _title
	(%PetitionFrameCharterName as Label).text = _title
	(%PetitionFrameMasterName as Label).text = session.get_object_name(_owner)
	(%PetitionFrameInstructions as Label).text = WowStrings.get_text(
		"GUILD_PETITION_LEADER_INSTRUCTIONS" if mine else "GUILD_PETITION_MEMBER_INSTRUCTIONS"
	)
	%PetitionFrameRequestButton.visible = mine
	%PetitionFrameSignButton.visible = not mine
	%PetitionFrameRequestButton.disabled = _signers.size() >= SIGNATURES
	for i: int in SIGNATURES:
		var label: Label = get_node("%%PetitionFrameMemberName%d" % (i + 1))
		label.text = session.get_object_name(_signers[i]) if i < _signers.size() \
		else WowStrings.get_text("NOT_YET_SIGNED")


func _on_sign_result(result: GuildRegistrarFrame.Sign) -> void:
	if result == GuildRegistrarFrame.Sign.OK:
		message_added.emit(WowStrings.get_text("ERR_PETITION_SIGNED"))
		show_signatures(_item)
		return
	error_raised.emit(
		WowStrings.get_text(GuildRegistrarFrame.SIGN_ERRORS.get(result, "ERR_GUILD_INTERNAL"))
	)
