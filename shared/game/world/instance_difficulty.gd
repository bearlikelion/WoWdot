class_name InstanceDifficulty
extends RefCounted

signal changed
signal announced(text: String)

# Map.dbc InstanceType.
enum InstanceType { NONE, PARTY, RAID, PVP, ARENA }

const DUNGEON_MODES: int = 2
const RAID_MODES: int = 4

var dungeon: int = 0
var raid: int = 0
# The current map's difficulty from SMSG_INSTANCE_DIFFICULTY, and whether its raid lets heroic toggle.
var instance: int = 0
var dynamic: bool = false
var map_id: int = 0

var _known_dungeon: bool = false
var _known_raid: bool = false
var _session: WowSession


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)
	session.world_entered.connect(
		func(map: int, _at: Vector3, _facing: float) -> void: map_id = map
	)


# The server answers only a refusal, with the old mode, so the new one takes hold at once.
func set_dungeon(mode: int) -> void:
	_send("MSG_SET_DUNGEON_DIFFICULTY", mode)
	_known_dungeon = true
	_on_dungeon(mode)


func set_raid(mode: int) -> void:
	_send("MSG_SET_RAID_DIFFICULTY", mode)
	_known_raid = true
	_on_raid(mode)


func instance_type() -> InstanceType:
	var maps: WowDBC = WowDBC.open(WowAssets.archive, "Map")
	var row: int = maps.find(map_id)
	return maps.get_uint(row, "InstanceType") as InstanceType if row >= 0 else InstanceType.NONE


# MapDifficulty.dbc's player cap for the current map at its difficulty, or 0.
func max_players() -> int:
	var table: WowDBC = WowDBC.open(WowAssets.archive, "MapDifficulty")
	for row: int in table.row_count():
		if table.get_uint(row, "MapID") == map_id and table.get_uint(row, "Difficulty") == instance:
			return table.get_uint(row, "MaxPlayers")
	return 0


func _send(opcode: String, mode: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_u32(0, mode)
	_session.send_packet(opcode, payload)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_INSTANCE_DIFFICULTY":
			instance = reader.u32()
			dynamic = reader.u32() != 0
		"MSG_SET_DUNGEON_DIFFICULTY":
			_on_dungeon(reader.u32())
			_known_dungeon = true
			return
		"MSG_SET_RAID_DIFFICULTY":
			_on_raid(reader.u32())
			_known_raid = true
			return
		_:
			return
	changed.emit()


func _on_dungeon(mode: int) -> void:
	if _known_dungeon and mode != dungeon:
		_announce("ERR_DUNGEON_DIFFICULTY_CHANGED_S", "DUNGEON_DIFFICULTY%d" % (mode + 1))
	dungeon = mode
	changed.emit()


func _on_raid(mode: int) -> void:
	if _known_raid and mode != raid:
		_announce("ERR_RAID_DIFFICULTY_CHANGED_S", "RAID_DIFFICULTY%d" % (mode + 1))
	raid = mode
	changed.emit()


func _announce(key: String, mode_key: String) -> void:
	announced.emit(WowStrings.format(WowStrings.get_text(key), [WowStrings.get_text(mode_key)]))
