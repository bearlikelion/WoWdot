class_name Calendar
extends RefCounted

signal changed
signal event_received(event: Dictionary)
signal pending_changed(count: int)
# An event's invites or details changed on the server, so an open event wants reading again.
signal event_updated
signal command_failed(text: String)

enum Rsvp {
	INVITED, ACCEPTED, DECLINED, CONFIRMED, OUT, STANDBY, SIGNED_UP, NOT_SIGNED_UP, TENTATIVE,
}

enum EventType { RAID, DUNGEON, PVP, MEETING, OTHER }
enum Rank { PLAYER, MODERATOR, OWNER }

# CalendarError codes against the strings the stock client shows for them.
const ERROR_KEYS: Dictionary[int, String] = {
	1: "CALENDAR_ERROR_GUILD_EVENTS_EXCEEDED", 2: "CALENDAR_ERROR_EVENTS_EXCEEDED",
	3: "CALENDAR_ERROR_SELF_INVITES_EXCEEDED", 4: "CALENDAR_ERROR_OTHER_INVITES_EXCEEDED",
	5: "CALENDAR_ERROR_PERMISSIONS", 6: "CALENDAR_ERROR_EVENT_INVALID",
	7: "CALENDAR_ERROR_NOT_INVITED", 8: "CALENDAR_ERROR_INTERNAL",
	9: "ERR_GUILD_PLAYER_NOT_IN_GUILD", 10: "CALENDAR_ERROR_ALREADY_INVITED_TO_EVENT_S",
	11: "ERR_LOOT_PLAYER_NOT_FOUND", 12: "CALENDAR_ERROR_NOT_ALLIED",
	13: "CALENDAR_ERROR_IGNORED", 14: "CALENDAR_ERROR_INVITES_EXCEEDED",
	16: "CALENDAR_ERROR_INVALID_DATE", 17: "CALENDAR_ERROR_INVALID_TIME",
	19: "CALENDAR_ERROR_NEEDS_TITLE", 20: "CALENDAR_ERROR_EVENT_PASSED",
	21: "CALENDAR_ERROR_EVENT_LOCKED", 22: "CALENDAR_ERROR_DELETE_CREATOR_FAILED",
	24: "ERR_SYSTEM_DISABLED", 25: "ERR_RESTRICTED_ACCOUNT",
	26: "CALENDAR_ERROR_ARENA_EVENTS_EXCEEDED", 27: "CALENDAR_ERROR_RESTRICTED_LEVEL",
	28: "ERR_USER_SQUELCHED", 29: "CALENDAR_ERROR_NO_INVITE",
	36: "CALENDAR_ERROR_EVENT_WRONG_SERVER", 37: "CALENDAR_ERROR_INVITE_WRONG_SERVER",
	38: "CALENDAR_ERROR_NO_GUILD_INVITES", 39: "CALENDAR_ERROR_INVALID_SIGNUP",
	40: "CALENDAR_ERROR_NO_MODERATOR",
}
const MAX_INVITES: int = 100
const NO_DUNGEON: int = -1
const HOLIDAY_DATES: int = 26
const HOLIDAY_DURATIONS: int = 10
const HOLIDAY_FLAGS: int = 10
# A packed date whose year field is all ones repeats every year.
const ANY_YEAR: int = 0x1F

# Pending invites as {event, invite, status, rank, guild_event}.
var invites: Array[Dictionary] = []
# The player's events as {id, title, type, time, flags, dungeon}, time as a Dictionary date.
var events: Array[Dictionary] = []
# Holidays the server announces as {id, dates, durations, texture}.
var holidays: Array[Dictionary] = []
# Raid and heroic saves as {map, difficulty, seconds_left, id}.
var raid_saves: Array[Dictionary] = []
var server_time: int = 0
var pending: int = 0

var _session: WowSession


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)
	session.state_changed.connect(_on_state_changed)


# AppendPackedTime's bit fields as a Time dictionary; the year is -1 when it repeats yearly.
static func unpack_time(packed: int) -> Dictionary:
	var year_bits: int = (packed >> 24) & 0x1F
	return {
		"minute": packed & 0x3F,
		"hour": (packed >> 6) & 0x1F,
		"day": ((packed >> 14) & 0x3F) + 1,
		"month": ((packed >> 20) & 0xF) + 1,
		"year": -1 if year_bits == ANY_YEAR else year_bits + 2000,
	}


# AppendPackedTime's layout, weekday included, from a Time date with year, month, day, hour, minute.
static func pack_time(date: Dictionary) -> int:
	var weekday: int = Time.get_datetime_dict_from_unix_time(
		Time.get_unix_time_from_datetime_dict(date)
	)["weekday"]
	return (int(date["year"]) - 2000) << 24 | (int(date["month"]) - 1) << 20 \
	| (int(date["day"]) - 1) << 14 | weekday << 11 | int(date["hour"]) << 6 | int(date["minute"])


func request() -> void:
	_session.send_packet("CMSG_CALENDAR_GET_CALENDAR", PackedByteArray())


func get_event(event_id: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, event_id)
	_session.send_packet("CMSG_CALENDAR_GET_EVENT", payload)


# A personal event; the creator lists itself as the owner, since the server adds only who is sent.
func add_event(title: String, description: String, type: EventType, date: Dictionary) -> void:
	var packed: int = pack_time(date)
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_data(title.to_utf8_buffer())
	buffer.put_u8(0)
	buffer.put_data(description.to_utf8_buffer())
	buffer.put_u8(0)
	buffer.put_u8(type)
	buffer.put_u8(0)
	buffer.put_u32(MAX_INVITES)
	buffer.put_32(NO_DUNGEON)
	buffer.put_u32(packed)
	buffer.put_u32(packed)
	buffer.put_u32(0)
	buffer.put_u32(1)
	buffer.put_data(PacketReader.pack_guid(_session.get_player_guid()))
	buffer.put_u8(Rsvp.CONFIRMED)
	buffer.put_u8(Rank.OWNER)
	_session.send_packet("CMSG_CALENDAR_ADD_EVENT", buffer.data_array)


# CMSG_CALENDAR_UPDATE_EVENT: the event and the owner's invite, then the fields as when added.
func update_event(
	event_id: int, invite_id: int, title: String, description: String, type: EventType,
	date: Dictionary,
) -> void:
	var packed: int = pack_time(date)
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u64(event_id)
	buffer.put_u64(invite_id)
	buffer.put_data(title.to_utf8_buffer())
	buffer.put_u8(0)
	buffer.put_data(description.to_utf8_buffer())
	buffer.put_u8(0)
	buffer.put_u8(type)
	buffer.put_u8(0)
	buffer.put_u32(MAX_INVITES)
	buffer.put_32(NO_DUNGEON)
	buffer.put_u32(packed)
	buffer.put_u32(packed)
	buffer.put_u32(0)
	_session.send_packet("CMSG_CALENDAR_UPDATE_EVENT", buffer.data_array)


func request_pending() -> void:
	_session.send_packet("CMSG_CALENDAR_GET_NUM_PENDING", PackedByteArray())


func remove_event(event_id: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(20)
	payload.encode_u64(0, event_id)
	_session.send_packet("CMSG_CALENDAR_REMOVE_EVENT", payload)


func invite(event_id: int, invite_id: int, player_name: String) -> void:
	var payload: PackedByteArray = []
	payload.resize(16)
	payload.encode_u64(0, event_id)
	payload.encode_u64(8, invite_id)
	payload.append_array(player_name.to_utf8_buffer())
	payload.append_array(PackedByteArray([0, 0, 0]))
	_session.send_packet("CMSG_CALENDAR_EVENT_INVITE", payload)


func rsvp(event_id: int, invite_id: int, status: Rsvp) -> void:
	var payload: PackedByteArray = []
	payload.resize(20)
	payload.encode_u64(0, event_id)
	payload.encode_u64(8, invite_id)
	payload.encode_u32(16, status)
	_session.send_packet("CMSG_CALENDAR_EVENT_RSVP", payload)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode == "SMSG_CALENDAR_SEND_CALENDAR":
		_read_calendar(PacketReader.new(payload))
	elif opcode == "SMSG_CALENDAR_SEND_EVENT":
		event_received.emit(_read_event(PacketReader.new(payload)))
	elif opcode == "SMSG_CALENDAR_SEND_NUM_PENDING":
		pending = payload.decode_u32(0)
		pending_changed.emit(pending)
	elif opcode == "SMSG_CALENDAR_COMMAND_RESULT":
		_read_result(PacketReader.new(payload))
	elif opcode.begins_with("SMSG_CALENDAR_EVENT_"):
		request()
		request_pending()
		event_updated.emit()


# SMSG_CALENDAR_COMMAND_RESULT: a player's name, empty unless the error names one, then the code.
func _read_result(reader: PacketReader) -> void:
	reader.u32()
	reader.u8()
	var param: String = reader.cstring()
	var error: int = reader.u32()
	request()
	if error == 0:
		return
	var key: String = ERROR_KEYS.get(error, "CALENDAR_ERROR_INTERNAL")
	command_failed.emit(WowStrings.format(WowStrings.get_text(key), [param]))


# The stock client asks how many invites wait once it is in the world.
func _on_state_changed(state: int, _message: String) -> void:
	if state == WowSession.STATE_IN_WORLD and PacketReader.wotlk:
		request_pending()


func _read_calendar(reader: PacketReader) -> void:
	invites.clear()
	for i: int in reader.u32():
		var invite: Dictionary = {
			"event": reader.u64(),
			"invite": reader.u64(),
			"status": reader.u8(),
			"rank": reader.u8(),
			"guild_event": reader.u8() != 0,
		}
		reader.packed_guid()
		invites.append(invite)
	events.clear()
	for i: int in reader.u32():
		var event: Dictionary = {
			"id": reader.u64(), "title": reader.cstring(), "type": reader.u32(),
		}
		event["time"] = unpack_time(reader.u32())
		event["flags"] = reader.u32()
		event["dungeon"] = reader.i32()
		reader.packed_guid()
		events.append(event)
	server_time = reader.u32()
	reader.skip(4)
	raid_saves.clear()
	for i: int in reader.u32():
		raid_saves.append({
			"map": reader.u32(), "difficulty": reader.u32(), "seconds_left": reader.u32(),
			"id": reader.u64(),
		})
	reader.skip(4)
	# Raid resets carry a map, period and offset each.
	reader.skip(reader.u32() * 12)
	holidays.clear()
	for i: int in reader.u32():
		var holiday: Dictionary = {"id": reader.u32()}
		reader.skip(16)
		var dates: Array[int] = []
		for j: int in HOLIDAY_DATES:
			dates.append(reader.u32())
		var durations: Array[int] = []
		for j: int in HOLIDAY_DURATIONS:
			durations.append(reader.u32())
		reader.skip(HOLIDAY_FLAGS * 4)
		holiday["dates"] = dates
		holiday["durations"] = durations
		holiday["texture"] = reader.cstring()
		holidays.append(holiday)
	changed.emit()


# SMSG_CALENDAR_SEND_EVENT: the creator and details, then each invite with its status and note.
func _read_event(reader: PacketReader) -> Dictionary:
	reader.u8()
	var event: Dictionary = {"creator": reader.packed_guid(), "id": reader.u64()}
	event["title"] = reader.cstring()
	event["description"] = reader.cstring()
	event["type"] = reader.u8()
	reader.u8()
	reader.u32()
	event["dungeon"] = reader.i32()
	event["flags"] = reader.u32()
	event["time"] = unpack_time(reader.u32())
	reader.u32()
	event["guild"] = reader.u32()
	var invites_list: Array[Dictionary] = []
	for i: int in reader.u32():
		var entry: Dictionary = {"guid": reader.packed_guid(), "level": reader.u8()}
		entry["status"] = reader.u8()
		entry["rank"] = reader.u8()
		entry["guild_event"] = reader.u8() != 0
		entry["invite"] = reader.u64()
		reader.u32()
		entry["note"] = reader.cstring()
		invites_list.append(entry)
	event["invites"] = invites_list
	return event
