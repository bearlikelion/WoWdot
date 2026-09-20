class_name Channels
extends RefCounted

# SMSG_CHANNEL_NOTIFY types, with the GlobalStrings line each one prints.
enum Notice { JOINED = 0x00, LEFT = 0x01, YOU_JOINED = 0x02, YOU_LEFT = 0x03,
	WRONG_PASSWORD = 0x04, NOT_MEMBER = 0x05, NOT_MODERATOR = 0x06, MUTED = 0x08,
	BANNED = 0x0A, INVALID_NAME = 0x11, NOT_MODERATED = 0x12 }

const NOTICE_KEYS: Dictionary[Notice, String] = {
	Notice.YOU_JOINED: "CHAT_YOU_JOINED_NOTICE",
	Notice.YOU_LEFT: "CHAT_YOU_LEFT_NOTICE",
	Notice.WRONG_PASSWORD: "CHAT_WRONG_PASSWORD_NOTICE",
	Notice.NOT_MEMBER: "CHAT_NOT_MEMBER_NOTICE",
	Notice.NOT_MODERATOR: "CHAT_NOT_MODERATOR_NOTICE",
	Notice.MUTED: "CHAT_MUTED_NOTICE",
	Notice.BANNED: "CHAT_BANNED_NOTICE",
	Notice.INVALID_NAME: "CHAT_INVALID_NAME_NOTICE",
}

# Channel numbers are the client's own, counted in the order this character joined.
static var joined: PackedStringArray = []


static func join(channel_name: String, password: String = "") -> void:
	var payload: PackedByteArray = channel_name.to_utf8_buffer()
	payload.append(0)
	payload.append_array(password.to_utf8_buffer())
	payload.append(0)
	WowClient.session.send_packet("CMSG_JOIN_CHANNEL", payload)


static func leave(channel_name: String) -> void:
	var payload: PackedByteArray = channel_name.to_utf8_buffer()
	payload.append(0)
	WowClient.session.send_packet("CMSG_LEAVE_CHANNEL", payload)


# The server capitalises channel names, so its spelling is the one kept.
static func number_of(channel_name: String) -> int:
	for i: int in joined.size():
		if joined[i].nocasecmp_to(channel_name) == 0:
			return i + 1
	return 0


static func name_at(number: int) -> String:
	return joined[number - 1] if number >= 1 and number <= joined.size() else ""


# The system line a notice prints, keeping the joined list in step.
static func notice(payload: PackedByteArray) -> String:
	var reader: PacketReader = PacketReader.new(payload)
	var type: Notice = reader.u8() as Notice
	var channel_name: String = reader.text(payload.size() - 1)
	var at: int = number_of(channel_name) - 1
	if type == Notice.YOU_JOINED and at < 0:
		joined.append(channel_name)
	elif type == Notice.YOU_LEFT and at >= 0:
		joined.remove_at(at)
	var key: String = NOTICE_KEYS.get(type, "")
	if key.is_empty():
		return ""
	var text: String = WowStrings.get_text(key, "%s")
	var number: int = number_of(channel_name)
	var label: String = "%d. %s" % [number, channel_name] if number > 0 else channel_name
	return text % label if text.count("%s") == 1 else text


static func forget() -> void:
	joined.clear()
