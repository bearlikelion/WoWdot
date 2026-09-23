class_name Channels
extends RefCounted

# SMSG_CHANNEL_NOTIFY types, in wire order; each prints GlobalStrings CHAT_<name>_NOTICE.
enum Notice { JOINED, LEFT, YOU_JOINED, YOU_LEFT, WRONG_PASSWORD, NOT_MEMBER, NOT_MODERATOR,
	PASSWORD_CHANGED, OWNER_CHANGED, PLAYER_NOT_FOUND, NOT_OWNER, CHANNEL_OWNER, MODE_CHANGE,
	ANNOUNCEMENTS_ON, ANNOUNCEMENTS_OFF, MODERATION_ON, MODERATION_OFF, MUTED, PLAYER_KICKED,
	BANNED, PLAYER_BANNED, PLAYER_UNBANNED, PLAYER_NOT_BANNED, PLAYER_ALREADY_MEMBER, INVITE,
	INVITE_WRONG_FACTION, WRONG_FACTION, INVALID_NAME, NOT_MODERATED, PLAYER_INVITED,
	PLAYER_INVITE_BANNED, THROTTLED }

# Notices that name one player by guid, by name, or a player and who acted on them.
const GUID_NOTICES: Array[Notice] = [
	Notice.PASSWORD_CHANGED, Notice.OWNER_CHANGED, Notice.ANNOUNCEMENTS_ON,
	Notice.ANNOUNCEMENTS_OFF, Notice.MODERATION_ON, Notice.MODERATION_OFF,
	Notice.PLAYER_ALREADY_MEMBER, Notice.INVITE,
]
const NAME_NOTICES: Array[Notice] = [
	Notice.PLAYER_NOT_FOUND, Notice.CHANNEL_OWNER, Notice.PLAYER_NOT_BANNED,
	Notice.PLAYER_INVITED, Notice.PLAYER_INVITE_BANNED,
]
const PAIR_NOTICES: Array[Notice] = [
	Notice.PLAYER_KICKED, Notice.PLAYER_BANNED, Notice.PLAYER_UNBANNED,
]
# Slash commands that send the channel and, for most, a player name.
const COMMANDS: Dictionary[String, String] = {
	"chatlist": "CMSG_CHANNEL_LIST", "chatwho": "CMSG_CHANNEL_LIST",
	"chatinfo": "CMSG_CHANNEL_LIST",
	"password": "CMSG_CHANNEL_PASSWORD", "pass": "CMSG_CHANNEL_PASSWORD",
	"owner": "CMSG_CHANNEL_SET_OWNER", "mod": "CMSG_CHANNEL_MODERATOR",
	"moderator": "CMSG_CHANNEL_MODERATOR", "unmod": "CMSG_CHANNEL_UNMODERATOR",
	"unmoderator": "CMSG_CHANNEL_UNMODERATOR", "mute": "CMSG_CHANNEL_MUTE",
	"squelch": "CMSG_CHANNEL_MUTE", "unvoice": "CMSG_CHANNEL_MUTE",
	"unmute": "CMSG_CHANNEL_UNMUTE", "unsquelch": "CMSG_CHANNEL_UNMUTE",
	"voice": "CMSG_CHANNEL_UNMUTE", "chatinvite": "CMSG_CHANNEL_INVITE",
	"cinvite": "CMSG_CHANNEL_INVITE", "ckick": "CMSG_CHANNEL_KICK",
	"ban": "CMSG_CHANNEL_BAN", "unban": "CMSG_CHANNEL_UNBAN",
	"announce": "CMSG_CHANNEL_ANNOUNCEMENTS", "ann": "CMSG_CHANNEL_ANNOUNCEMENTS",
	"moderate": "CMSG_CHANNEL_MODERATE",
}

# ChatChannels.dbc and AreaTable.dbc flags.
enum ChannelFlag { INITIAL = 0x01, ZONE_DEPENDENT = 0x02, CITY_ONLY = 0x10 }
const AREA_FLAG_CAPITAL: int = 0x100

# Channel numbers are the client's own; a channel left frees its number for the next one joined.
static var joined: PackedStringArray = []

static var _zone_channels: PackedStringArray = []


static func join(channel_name: String, password: String = "") -> void:
	var payload: PackedByteArray = []
	# 3.3.5a leads with a channel id, a voice flag and a zone-update flag.
	if String(WowLoader.profile()["id"]) == "wotlk":
		payload.resize(6)
	payload.append_array(channel_name.to_utf8_buffer())
	payload.append(0)
	payload.append_array(password.to_utf8_buffer())
	payload.append(0)
	WowClient.session.send_packet("CMSG_JOIN_CHANNEL", payload)


static func leave(channel_name: String) -> void:
	var payload: PackedByteArray = []
	if PacketReader.wotlk:
		payload.resize(4)
	payload.append_array(channel_name.to_utf8_buffer())
	payload.append(0)
	WowClient.session.send_packet("CMSG_LEAVE_CHANNEL", payload)


# Swaps the zone's default channels, as the stock client does on its own.
static func enter_zone(zone_name: String, area_flags: int) -> void:
	var wanted: PackedStringArray = []
	var channels: WowDBC = WowDBC.open(WowAssets.archive, "ChatChannels")
	var capital: bool = area_flags & AREA_FLAG_CAPITAL != 0
	for row: int in channels.row_count():
		var flags: int = channels.get_uint(row, "Flags")
		if flags & ChannelFlag.INITIAL == 0 or (flags & ChannelFlag.CITY_ONLY != 0 and not capital):
			continue
		var channel_name: String = channels.get_string(row, "Name")
		if flags & ChannelFlag.ZONE_DEPENDENT != 0:
			var place: String = WowStrings.get_text("CITY", "City") \
					if flags & ChannelFlag.CITY_ONLY != 0 else zone_name
			channel_name = channel_name.replace("%s", place)
		wanted.append(channel_name)
	for channel_name: String in _zone_channels:
		if channel_name not in wanted:
			leave(channel_name)
	for channel_name: String in wanted:
		if channel_name not in _zone_channels:
			join(channel_name)
	_zone_channels = wanted


# The server capitalises channel names, so its spelling is the one kept.
static func number_of(channel_name: String) -> int:
	for i: int in joined.size():
		if not channel_name.is_empty() and joined[i].nocasecmp_to(channel_name) == 0:
			return i + 1
	return 0


static func name_at(number: int) -> String:
	return joined[number - 1] if number >= 1 and number <= joined.size() else ""


# Runs "/owner 1 Name" and its kin; a bare "/owner 1" asks who owns the channel.
static func run_command(command: String, words: PackedStringArray) -> bool:
	var opcode: String = COMMANDS.get(command, "")
	if opcode.is_empty() or words.is_empty():
		return false
	var channel_name: String = name_at(words[0].to_int()) if words[0].is_valid_int() else words[0]
	if opcode == "CMSG_CHANNEL_SET_OWNER" and words.size() == 1:
		opcode = "CMSG_CHANNEL_OWNER"
	var payload: PackedByteArray = channel_name.to_utf8_buffer()
	payload.append(0)
	if words.size() > 1:
		payload.append_array(words[1].to_utf8_buffer())
		payload.append(0)
	WowClient.session.send_packet(opcode, payload)
	return true


# The system line a notice prints, keeping the joined list in step.
static func notice(payload: PackedByteArray) -> String:
	var session: WowSession = WowClient.session
	var reader: PacketReader = PacketReader.new(payload)
	var raw_type: int = reader.u8()
	if raw_type >= Notice.size():
		return ""
	var type: Notice = raw_type as Notice
	var channel_name: String = reader.cstring()
	var at: int = number_of(channel_name) - 1
	if type == Notice.YOU_JOINED and at < 0:
		var free: int = joined.find("")
		if free < 0:
			joined.append(channel_name)
		else:
			joined[free] = channel_name
	elif type == Notice.YOU_LEFT and at >= 0:
		joined[at] = ""
	# Everyone coming and going would drown a busy channel, as it would the stock client.
	if type in [Notice.JOINED, Notice.LEFT, Notice.MODE_CHANGE]:
		return ""
	var number: int = number_of(channel_name)
	var args: Array = ["%d. %s" % [number, channel_name] if number > 0 else channel_name]
	if type in GUID_NOTICES:
		args.append(session.get_object_name(reader.u64()))
	elif type in NAME_NOTICES:
		args.append(reader.cstring())
	elif type in PAIR_NOTICES:
		var affected: int = reader.u64()
		args.append_array([session.get_object_name(affected), session.get_object_name(reader.u64())])
	var key: String = "CHAT_%s_NOTICE" % Notice.keys()[type]
	var text: String = WowStrings.get_text(key, "")
	# 3.3.5 links the channel by number first: "Joined Channel: |Hchannel:%d|h[%s]|h".
	if text.contains("|Hchannel:%d"):
		args.push_front(number)
	return WowStrings.format(text, args) if text != key else ""


# SMSG_CHANNEL_LIST: the channel, its flags, then each member's guid and flags.
static func members(payload: PackedByteArray) -> Dictionary:
	var reader: PacketReader = PacketReader.new(payload)
	if PacketReader.wotlk:
		reader.u8()
	var channel_name: String = reader.cstring()
	reader.u8()
	var guids: PackedInt64Array = []
	for i: int in reader.u32():
		guids.append(reader.u64())
		reader.u8()
	return {"channel": channel_name, "guids": guids}


static func forget() -> void:
	joined.clear()
	_zone_channels.clear()
