class_name RuneFrame
extends Control

enum RuneType { BLOOD = 1, UNHOLY = 2, FROST = 3, DEATH = 4 }

const DEATH_KNIGHT: int = 6
const RUNE_COUNT: int = 6
# RUNE_BASE_COOLDOWN; haste shortens it, and the server's resyncs correct the drift.
const RECHARGE_MSEC: int = 10000
const FULL_RECHARGE: int = 255
# Each button shows the rune its id names: blood, blood, frost, frost, unholy, unholy.
const BUTTON_RUNES: Array[int] = [0, 1, 4, 5, 2, 3]
const DEFAULT_TYPES: Array[RuneType] = [
	RuneType.BLOOD, RuneType.BLOOD, RuneType.UNHOLY, RuneType.UNHOLY, RuneType.FROST, RuneType.FROST,
]
const RUNE_TEXTURES: Dictionary[RuneType, String] = {
	RuneType.BLOOD: "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Blood.blp",
	RuneType.UNHOLY: "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Unholy.blp",
	RuneType.FROST: "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Frost.blp",
	RuneType.DEATH: "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Death.blp",
}

var _types: Array[RuneType] = DEFAULT_TYPES.duplicate()


func _ready() -> void:
	var session: WowSession = WowClient.session
	session.packet_received.connect(_on_packet_received)
	session.runes_spent.connect(_on_runes_spent)
	session.object_updated.connect(_on_object_updated)
	_on_object_updated(session.get_player_guid())
	for rune: int in RUNE_COUNT:
		_show_type(rune)


func _on_object_updated(guid: int) -> void:
	var session: WowSession = WowClient.session
	if guid == session.get_player_guid():
		visible = (session.get_field(guid, "UNIT_FIELD_BYTES_0") >> 8) & 0xFF == DEATH_KNIGHT


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_RESYNC_RUNES":
			for rune: int in mini(reader.u32(), RUNE_COUNT):
				_types[rune] = reader.u8() as RuneType
				_show_type(rune)
				_recharge(rune, reader.u8())
		"SMSG_ADD_RUNE_POWER":
			var mask: int = reader.u32()
			for rune: int in RUNE_COUNT:
				if mask & (1 << rune):
					_recharge(rune, FULL_RECHARGE)
		"SMSG_CONVERT_RUNE":
			var rune: int = reader.u8()
			if rune < RUNE_COUNT:
				_types[rune] = reader.u8() as RuneType
				_show_type(rune)


func _on_runes_spent(ready_mask: int, recharged: PackedByteArray) -> void:
	for rune: int in RUNE_COUNT:
		if not ready_mask & (1 << rune) and rune < recharged.size():
			_recharge(rune, recharged[rune])


func _show_type(rune: int) -> void:
	var art: WowTexture = WowTexture.new()
	art.file = RUNE_TEXTURES.get(_types[rune], RUNE_TEXTURES[RuneType.BLOOD])
	var icon: TextureRect = get_node("%%RuneButtonIndividual%dRune" % (BUTTON_RUNES.find(rune) + 1))
	icon.texture = art


# Passed recharge comes out of 255; a full one means the rune is ready.
func _recharge(rune: int, passed: int) -> void:
	var cooldown: WowCooldown = get_node(
		"%%RuneButtonIndividual%dCooldown" % (BUTTON_RUNES.find(rune) + 1)
	)
	if passed >= FULL_RECHARGE:
		cooldown.stop()
		return
	var elapsed: int = roundi(RECHARGE_MSEC * passed / float(FULL_RECHARGE))
	cooldown.start(Time.get_ticks_msec() - elapsed, RECHARGE_MSEC)
