class_name Calendar
extends RefCounted

signal changed

enum Rsvp {
	INVITED, ACCEPTED, DECLINED, CONFIRMED, OUT, STANDBY, SIGNED_UP, NOT_SIGNED_UP, TENTATIVE,
}

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
var server_time: int = 0

var _session: WowSession


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)


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


func request() -> void:
	_session.send_packet("CMSG_CALENDAR_GET_CALENDAR", PackedByteArray())


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
	elif opcode.begins_with("SMSG_CALENDAR_EVENT_") or opcode == "SMSG_CALENDAR_COMMAND_RESULT":
		request()


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
	# Instance saves carry a map, difficulty, seconds left and a guid each.
	reader.skip(reader.u32() * 20)
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
