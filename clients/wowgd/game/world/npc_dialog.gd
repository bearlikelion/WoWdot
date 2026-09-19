class_name NpcDialog
extends RefCounted

# SMSG_QUESTGIVER_STATUS values.
enum Status { NONE, UNAVAILABLE, CHAT, INCOMPLETE, REWARD_REP, AVAILABLE, REWARD_OLD, REWARD2 }

const NPC_FLAG_GOSSIP: int = 0x01
const NPC_FLAG_QUESTGIVER: int = 0x02
# The talk-to-me models that float over quest givers.
const MARKERS: Dictionary[Status, String] = {
	Status.UNAVAILABLE: "Interface\\Buttons\\TalkToMeGrey.m2",
	Status.INCOMPLETE: "Interface\\Buttons\\TalkToMeQuestion_Grey.m2",
	Status.REWARD_REP: "Interface\\Buttons\\TalkToMeQuestionMark.m2",
	Status.AVAILABLE: "Interface\\Buttons\\TalkToMe.m2",
	Status.REWARD_OLD: "Interface\\Buttons\\TalkToMeQuestionMark.m2",
	Status.REWARD2: "Interface\\Buttons\\TalkToMeQuestionMark.m2",
}


# The npc guid, then each value as 32 bits, which is how every gossip and quest giver request reads.
static func send(opcode: String, guid: int, values: Array[int] = []) -> void:
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(8 + values.size() * 4)
	payload.encode_u64(0, guid)
	for i: int in values.size():
		payload.encode_u32(8 + i * 4, values[i])
	WowClient.session.send_packet(opcode, payload)


static func is_quest_giver(guid: int) -> bool:
	return WowClient.session.get_field(guid, "UNIT_NPC_FLAGS") & NPC_FLAG_QUESTGIVER != 0


# Right-clicking a unit opens its gossip when it has one, otherwise its quests; false for neither.
static func interact(guid: int) -> bool:
	var flags: int = WowClient.session.get_field(guid, "UNIT_NPC_FLAGS")
	if flags & NPC_FLAG_GOSSIP:
		send("CMSG_GOSSIP_HELLO", guid)
	elif flags & NPC_FLAG_QUESTGIVER:
		send("CMSG_QUESTGIVER_HELLO", guid)
	else:
		return false
	return true


# GetGossipText: one of the NPC text's options by weight, in the player's gender where it differs.
static func npc_text(options: Array) -> String:
	var total: float = 0.0
	for option: Array in options:
		total += option[0]
	var roll: float = randf() * total
	var picked: Array = options[0] if not options.is_empty() else []
	for option: Array in options:
		roll -= option[0]
		if option[0] > 0.0 and roll <= 0.0:
			picked = option
			break
	if picked.is_empty():
		return ""
	var session: WowSession = WowClient.session
	var female: bool = (session.get_field(session.get_player_guid(), "UNIT_FIELD_BYTES_0") >> 16) \
	& 0xFF == 1
	var text: String = picked[2] if female and not picked[2].is_empty() else picked[1]
	return QuestLog.format_text(text if not text.is_empty() else picked[2])
