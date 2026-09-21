class_name Tutorials
extends RefCounted

signal queue_changed

# 0-based bits of SMSG_TUTORIAL_FLAGS, named by their TUTORIAL_TITLE.
enum Id {
	QUESTGIVERS = 0x00,
	MOVEMENT = 0x01,
	CAMERAS = 0x02,
	TARGETING = 0x03,
	LOOTING = 0x06,
	TALENTS = 0x0c,
	TRAINERS = 0x0d,
	VENDORS = 0x13,
	FRIENDS = 0x15,
	CHATTING = 0x16,
	DEATH = 0x18,
	JUMPING = 0x20,
	TRAVEL = 0x22,
	PROFESSIONS = 0x25,
	GROUPS = 0x26,
	WELCOME = 0x29,
}

const BANK_BYTES: int = 32
# The SMSG_LEVELUP_INFO handler's order: each fires once the new level reaches its threshold.
const LEVEL_TRIGGERS: Array[Array] = [
	[3, Id.CHATTING],
	[4, Id.TRAINERS],
	[4, Id.CAMERAS],
	[5, Id.GROUPS],
	[7, Id.FRIENDS],
	[7, Id.PROFESSIONS],
	[8, Id.JUMPING],
	[10, Id.TALENTS],
]

# Waiting alert buttons, oldest first; the HUD may not exist yet when the first ones fire.
var queue: Array[Id] = []

var _session: WowSession
# Fired tutorials; a superset of the acknowledged bank, and empty until the server's flags land.
var _fired: PackedByteArray = PackedByteArray()
var _acknowledged: PackedByteArray = PackedByteArray()


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)
	session.world_entered.connect(_on_world_entered)
	session.leveled_up.connect(_on_leveled_up)
	session.merchant_inventory_received.connect(_on_window_opened.bind(Id.VENDORS))
	session.taxi_nodes_received.connect(_on_window_opened.bind(Id.TRAVEL))
	session.trainer_list_received.connect(_on_window_opened.bind(Id.TRAINERS))


func trigger(id: Id) -> void:
	if _fired.is_empty() or _bit(_fired, id):
		return
	_set_bit(_fired, id)
	queue.append(id)
	queue_changed.emit()


# FlagTutorial: doing the thing, or reading its window, stops it coming back on this account.
func acknowledge(id: Id) -> void:
	queue.erase(id)
	queue_changed.emit()
	if _acknowledged.is_empty() or _bit(_acknowledged, id):
		return
	_set_bit(_fired, id)
	_set_bit(_acknowledged, id)
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(4)
	payload.encode_u32(0, id)
	_session.send_packet("CMSG_TUTORIAL_FLAG", payload)


# ClearTutorials: the window's checkbox turns every tutorial off.
func clear() -> void:
	_fired.fill(0xFF)
	_acknowledged.fill(0xFF)
	_session.send_packet("CMSG_TUTORIAL_CLEAR", PackedByteArray())
	queue.clear()
	queue_changed.emit()


func _on_leveled_up(level: int, _health: int, _mana: int, _stats: PackedInt32Array) -> void:
	for entry: Array in LEVEL_TRIGGERS:
		if level >= entry[0]:
			trigger(entry[1] as Id)


func _bit(bank: PackedByteArray, id: int) -> bool:
	return bank[id >> 3] & (1 << (id & 7)) != 0


func _set_bit(bank: PackedByteArray, id: int) -> void:
	bank[id >> 3] |= 1 << (id & 7)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_TUTORIAL_FLAGS" or payload.size() < BANK_BYTES:
		return
	_fired = payload.slice(0, BANK_BYTES)
	_acknowledged = payload.slice(0, BANK_BYTES)


# Opening the trainer window counts as having read about trainers; the others fire their popup.
func _on_window_opened(_contents: Dictionary, id: Id) -> void:
	if id == Id.TRAINERS:
		acknowledge(id)
	else:
		trigger(id)


func _on_world_entered(_map_id: int, _position: Vector3, _orientation: float) -> void:
	trigger(Id.WELCOME)
	trigger(Id.QUESTGIVERS)
