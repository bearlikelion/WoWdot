class_name QuestPOIs
extends RefCounted

signal changed

# QuestPOI's objective index for the place a finished quest is handed in.
const TURN_IN: int = -1
# HandleQuestPOIQuery answers at most this many quests at a time.
const MAX_QUERY: int = 25

# Quest id to its POIs, each {objective, map, area, floor, points} with points in world yards.
var pois: Dictionary[int, Array] = {}

var _session: WowSession


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)


# CMSG_QUEST_POI_QUERY for the quests not asked about yet.
func query(quest_ids: Array[int]) -> void:
	var wanted: Array[int] = []
	for id: int in quest_ids:
		if not pois.has(id):
			wanted.append(id)
	for first: int in range(0, wanted.size(), MAX_QUERY):
		var batch: Array[int] = wanted.slice(first, first + MAX_QUERY)
		var payload: PackedByteArray = []
		payload.resize(4 + batch.size() * 4)
		payload.encode_u32(0, batch.size())
		for i: int in batch.size():
			payload.encode_u32(4 + i * 4, batch[i])
		_session.send_packet("CMSG_QUEST_POI_QUERY", payload)


# The POI a quest shows on a WorldMapArea: its turn-in once complete, else its first objective.
func poi_on(quest_id: int, area: int, complete: bool) -> Dictionary:
	for poi: Dictionary in pois.get(quest_id, []):
		if poi["area"] == area and (poi["objective"] == TURN_IN) == complete:
			return poi
	return {}


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_QUEST_POI_QUERY_RESPONSE":
		return
	var reader: PacketReader = PacketReader.new(payload)
	for i: int in reader.u32():
		var quest_id: int = reader.u32()
		var entries: Array[Dictionary] = []
		for j: int in reader.u32():
			reader.u32()
			var poi: Dictionary = {
				"objective": reader.i32(), "map": reader.u32(), "area": reader.u32(),
				"floor": reader.u32(),
			}
			reader.skip(8)
			var points: PackedVector2Array = []
			for k: int in reader.u32():
				points.append(Vector2(reader.i32(), reader.i32()))
			poi["points"] = points
			entries.append(poi)
		pois[quest_id] = entries
	changed.emit()
