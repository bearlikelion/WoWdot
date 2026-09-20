class_name GameClock
extends RefCounted

const MINUTES_PER_DAY: float = 1440.0
# GAMETIME_DAWN and GAMETIME_DUSK from GameTime.lua.
const DAWN_MINUTE: float = 5.5 * 60.0
const DUSK_MINUTE: float = 21.0 * 60.0
# vMaNGOS sends 1 / 60: a game minute per real minute.
const DEFAULT_SPEED: float = 1.0 / 60.0

## Minute of the day to hold the clock at, for checks and screenshots; negative runs the clock.
var override_minute: float = -1.0

var _synced: bool = false
var _base_minute: float = 0.0
var _speed: float = DEFAULT_SPEED
var _synced_msec: int = 0


func _init(session: WowSession) -> void:
	session.packet_received.connect(_on_packet_received)


# The local clock stands in until the server's time arrives, as on the glue screens.
func minute() -> float:
	if override_minute >= 0.0:
		return override_minute
	if not _synced:
		var now: Dictionary = Time.get_time_dict_from_system()
		return now["hour"] * 60.0 + now["minute"]
	var elapsed: float = (Time.get_ticks_msec() - _synced_msec) / 1000.0
	return fposmod(_base_minute + elapsed * _speed, MINUTES_PER_DAY)


func is_night() -> bool:
	var now: float = minute()
	return now < DAWN_MINUTE or now >= DUSK_MINUTE


# The packed time keeps minutes in bits 0 to 5 and hours in bits 6 to 10.
func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_LOGIN_SETTIMESPEED" or payload.size() < 8:
		return
	var packed: int = payload.decode_u32(0)
	_base_minute = ((packed >> 6) & 0x1F) * 60.0 + (packed & 0x3F)
	_speed = payload.decode_float(4)
	_synced_msec = Time.get_ticks_msec()
	_synced = true
