class_name WeatherState
extends RefCounted

signal changed

enum Type { FINE = 0, RAIN = 1, SNOW = 2, STORM = 3 }

var type: Type = Type.FINE
## 0 to 1; vMaNGOS sends below 0.27 for weather too light to see.
var grade: float = 0.0
## The SoundEntries loop the server picked for this weather, 0 for none.
var sound_id: int = 0


func _init(session: WowSession) -> void:
	session.packet_received.connect(_on_packet_received)
	session.world_entered.connect(_on_world_entered)


func _on_world_entered(_map_id: int, _position: Vector3, _orientation: float) -> void:
	type = Type.FINE
	grade = 0.0
	sound_id = 0
	changed.emit()


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_WEATHER" or payload.size() < 8:
		return
	type = payload.decode_u32(0) as Type
	grade = clampf(payload.decode_float(4), 0.0, 1.0) if type != Type.FINE else 0.0
	sound_id = payload.decode_u32(8) if payload.size() >= 12 else 0
	changed.emit()
