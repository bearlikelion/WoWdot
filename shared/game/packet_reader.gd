class_name PacketReader
extends RefCounted
# Little-endian reads that give 0 past the end instead of erroring on a short packet.

# The 3.3.5 layouts the decoders branch on.
static var wotlk: bool = String(WowLoader.profile()["id"]) == "wotlk"

var _data: PackedByteArray
var _offset: int = 0


func _init(payload: PackedByteArray) -> void:
	_data = payload


func u8() -> int:
	var at: int = _take(1)
	return _data.decode_u8(at) if at >= 0 else 0


func u16() -> int:
	var at: int = _take(2)
	return _data.decode_u16(at) if at >= 0 else 0


func u32() -> int:
	var at: int = _take(4)
	return _data.decode_u32(at) if at >= 0 else 0


func i32() -> int:
	var at: int = _take(4)
	return _data.decode_s32(at) if at >= 0 else 0


func f32() -> float:
	var at: int = _take(4)
	return _data.decode_float(at) if at >= 0 else 0.0


func u64() -> int:
	var at: int = _take(8)
	return _data.decode_u64(at) if at >= 0 else 0


# The length a packet gives counts the terminator, which must not reach the decoder.
func text(length: int) -> String:
	var at: int = _take(length)
	if at < 0:
		return ""
	var bytes: PackedByteArray = _data.slice(at, at + length)
	var end: int = bytes.find(0)
	return bytes.slice(0, end if end >= 0 else bytes.size()).get_string_from_utf8()


# A NUL terminated string, as most packet strings are written.
func cstring() -> String:
	var start: int = _offset
	while _offset < _data.size() and _data[_offset] != 0:
		_offset += 1
	var text_bytes: PackedByteArray = _data.slice(start, _offset)
	_offset = mini(_offset + 1, _data.size())
	return text_bytes.get_string_from_utf8()


func packed_guid() -> int:
	var mask: int = u8()
	var guid: int = 0
	for i: int in 8:
		if mask & (1 << i):
			guid |= u8() << (8 * i)
	return guid


func skip(count: int) -> void:
	_take(count)


func remaining() -> int:
	return _data.size() - _offset


func _take(count: int) -> int:
	if _offset + count > _data.size():
		_offset = _data.size()
		return -1
	_offset += count
	return _offset - count
