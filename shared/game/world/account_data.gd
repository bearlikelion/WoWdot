class_name AccountData
extends RefCounted

# The server's copy of one of the stock client's cache files arrived.
signal received(type: Type, text: String)

# AccountDataType: even types belong to the account, odd ones to the character.
enum Type {
	GLOBAL_CONFIG, CHARACTER_CONFIG, GLOBAL_BINDINGS, CHARACTER_BINDINGS, GLOBAL_MACROS,
	CHARACTER_MACROS, CHARACTER_LAYOUT, CHARACTER_CHAT,
}

const TYPES: int = 8
# The server refuses anything that inflates past this.
const MAX_SIZE: int = 0xFFFF

var _session: WowSession
var _times_asked: bool = false


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)
	session.state_changed.connect(_on_state_changed)


# CMSG_UPDATE_ACCOUNT_DATA: the type, when it changed, its inflated size, then the zlib stream.
func save(type: Type, text: String) -> void:
	var raw: PackedByteArray = text.to_utf8_buffer()
	if raw.size() > MAX_SIZE:
		return
	var payload: PackedByteArray = []
	payload.resize(12)
	payload.encode_u32(0, type)
	payload.encode_u32(4, int(Time.get_unix_time_from_system()))
	payload.encode_u32(8, raw.size())
	if not raw.is_empty():
		payload.append_array(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	_session.send_packet("CMSG_UPDATE_ACCOUNT_DATA", payload)


func request(type: Type) -> void:
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_u32(0, type)
	_session.send_packet("CMSG_REQUEST_ACCOUNT_DATA", payload)


# The account's own times only follow CMSG_READY_FOR_ACCOUNT_DATA_TIMES, sent once per connection.
func _on_state_changed(state: int, _message: String) -> void:
	if state == WowSession.STATE_CONNECTING_WORLD:
		_times_asked = false
	elif state == WowSession.STATE_CHARACTER_LIST and PacketReader.wotlk and not _times_asked:
		_times_asked = true
		_session.send_packet("CMSG_READY_FOR_ACCOUNT_DATA_TIMES", PackedByteArray())


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if not PacketReader.wotlk:
		return
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		# The account's types answer the ready message and the character's come at world entry.
		"SMSG_ACCOUNT_DATA_TIMES":
			reader.u32()
			reader.u8()
			var mask: int = reader.u32()
			for type: int in TYPES:
				if mask & (1 << type) and reader.u32() != 0:
					request(type as Type)
		"SMSG_UPDATE_ACCOUNT_DATA":
			reader.u64()
			var type: Type = reader.u32() as Type
			reader.u32()
			var size: int = reader.u32()
			var text: String = ""
			if size > 0:
				text = payload.slice(20).decompress(size, FileAccess.COMPRESSION_DEFLATE) \
						.get_string_from_utf8()
			received.emit(type, text)

