class_name ServerNotices
extends RefCounted

# SMSG_QUESTGIVER_QUEST_FAILED and SMSG_QUESTGIVER_QUEST_INVALID reasons.
const QUEST_FAILURES: Dictionary[int, String] = {
	4: "ERR_QUEST_FAILED_INVENTORY_FULL", 16: "ERR_QUEST_FAILED_DUPLICATE_ITEM",
	17: "ERR_QUEST_FAILED_DUPLICATE_ITEM", 1: "ERR_QUEST_FAILED_LOW_LEVEL",
	6: "ERR_QUEST_FAILED_WRONG_RACE", 7: "ERR_QUEST_ALREADY_DONE",
	13: "ERR_QUEST_ALREADY_ON", 12: "ERR_QUEST_ONLY_ONE_TIMED",
	21: "ERR_QUEST_FAILED_NOT_ENOUGH_MONEY", 0: "ERR_QUEST_FAILED_MISSING_ITEMS",
}
# SMSG_INSTANCE_RESET_FAILED reasons.
const RESET_FAILURES: Dictionary[int, String] = {
	0: "INSTANCE_RESET_FAILED", 1: "INSTANCE_RESET_FAILED_OFFLINE",
	2: "INSTANCE_RESET_FAILED_ZONING",
}
# SMSG_PET_TAME_FAILURE reasons.
const PET_TAME_FAILURES: Dictionary[int, String] = {
	1: "PETTAME_INVALIDCREATURE", 2: "PETTAME_TOOMANY", 3: "PETTAME_CREATUREALREADYOWNED",
	4: "PETTAME_NOTTAMEABLE", 5: "PETTAME_ANOTHERSUMMONACTIVE", 6: "PETTAME_UNITSCANTTAME",
	7: "PETTAME_NOPETAVAILABLE", 8: "PETTAME_INTERNALERROR", 9: "PETTAME_TOOHIGHLEVEL",
	10: "PETTAME_DEAD", 11: "PETTAME_NOTDEAD",
}
# SMSG_MEETINGSTONE_SETQUEUE statuses and SMSG_MEETINGSTONE_JOINFAILED codes.
const MEETING_STONE_STATUS: Dictionary[int, String] = {
	0: "ERR_MEETING_STONE_LEFT_QUEUE_S", 1: "ERR_MEETING_STONE_IN_QUEUE_S",
	2: "ERR_MEETING_STONE_OTHER_MEMBER_LEFT", 3: "ERR_MEETING_STONE_PARTY_KICKED_FROM_QUEUE",
	4: "ERR_MEETING_STONE_MEMBER_STILL_IN_QUEUE",
}
const MEETING_STONE_FAILURES: Dictionary[int, String] = {
	1: "ERR_MEETING_STONE_MUST_BE_LEADER", 2: "ERR_MEETING_STONE_GROUP_FULL",
	3: "ERR_MEETING_STONE_NO_RAID_GROUP",
}
# SMSG_GMTICKET_CREATE, _UPDATETEXT and _DELETETICKET answers.
const TICKET_ANSWERS: Dictionary[int, String] = {
	1: "ERR_TICKET_ALREADY_EXISTS", 2: "TICKET_STATUS1", 3: "ERR_TICKET_CREATE_ERROR",
	5: "ERR_TICKET_UPDATE_ERROR", 7: "ERR_TICKET_DB_ERROR",
}
const TICKET_HAS_TEXT: int = 6
const TICKET_CATEGORY_GAMEPLAY: int = 1
# SMSG_RAID_INSTANCE_MESSAGE types.
const RAID_MESSAGES: Dictionary[int, String] = {
	1: "RAID_INSTANCE_WARNING_HOURS", 2: "RAID_INSTANCE_WARNING_MIN",
	3: "RAID_INSTANCE_WARNING_MIN_SOON", 4: "RAID_INSTANCE_WELCOME",
}
# SMSG_MOUNTRESULT and SMSG_DISMOUNTRESULT codes; the last of each is success.
const MOUNT_FAILURES: Array[String] = [
	"ERR_MOUNT_INVALIDMOUNTEE", "ERR_MOUNT_TOOFARAWAY", "ERR_MOUNT_ALREADYMOUNTED",
	"ERR_MOUNT_NOTMOUNTABLE", "ERR_MOUNT_NOTYOURPET", "ERR_MOUNT_OTHER", "ERR_MOUNT_LOOTING",
	"ERR_MOUNT_RACECANTMOUNT", "ERR_MOUNT_SHAPESHIFTED", "ERR_MOUNT_FORCEDDISMOUNT",
]
const DISMOUNT_FAILURES: Array[String] = [
	"ERR_DISMOUNT_NOPET", "ERR_DISMOUNT_NOTMOUNTED", "ERR_DISMOUNT_NOTYOURPET",
]
const DUEL_FORFEIT_SECONDS: int = 10

static var _maps: WowDBC
# The area queued for at a meeting stone, or 0.
static var meeting_stone_area: int = 0


# The chat line a server message prints, or nothing when the opcode is not one of these.
static func line(opcode: String, payload: PackedByteArray) -> String:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_ZONE_UNDER_ATTACK":
			var text: String = WowStrings.get_text("ZONE_UNDER_ATTACK")
			return WowStrings.format(text, [AreaInfo.area_name(reader.u32())])
		"SMSG_DEFENSE_MESSAGE":
			reader.u32()
			return reader.text(reader.u32())
		"SMSG_EXPLORATION_EXPERIENCE":
			var area: String = AreaInfo.area_name(reader.u32())
			var xp: int = reader.u32()
			var key: String = "ERR_ZONE_EXPLORED_XP" if xp > 0 else "ERR_ZONE_EXPLORED"
			return WowStrings.format(WowStrings.get_text(key), [area, xp])
		"SMSG_PLAYERBOUND":
			reader.u64()
			var home: String = AreaInfo.area_name(reader.u32())
			return WowStrings.format(WowStrings.get_text("ERR_DEATHBIND_SUCCESS_S"), [home])
		"SMSG_DURABILITY_DAMAGE_DEATH":
			return WowStrings.get_text("DURABILITYDAMAGE_DEATH").replace("%%", "%")
		"SMSG_PLAYED_TIME":
			var total: String = WowStrings.get_text("TIME_PLAYED_TOTAL") % _played(reader.u32())
			return total + "\n" + WowStrings.get_text("TIME_PLAYED_LEVEL") % _played(reader.u32())
		"SMSG_PVP_CREDIT":
			var honor: int = reader.i32()
			var victim: int = reader.u64()
			var race: int = WowClient.session.get_field(victim, "UNIT_FIELD_BYTES_0") & 0xFF
			var alliance: bool = CharacterOptions.faction(race) == CharacterOptions.Faction.ALLIANCE
			var rank: String = HonorFrame.rank_name(reader.i32(), alliance)
			var fallen: String = WowClient.session.get_object_name(victim)
			return WowStrings.format(WowStrings.get_text("COMBATLOG_HONORGAIN"), [fallen, rank, honor])
		"SMSG_MOUNTRESULT":
			var code: int = reader.u32()
			return WowStrings.get_text(MOUNT_FAILURES[code]) if code < MOUNT_FAILURES.size() else ""
		"SMSG_DISMOUNTRESULT":
			var code: int = reader.u32()
			if code >= DISMOUNT_FAILURES.size():
				return ""
			return WowStrings.get_text(DISMOUNT_FAILURES[code])
		"SMSG_DUEL_OUTOFBOUNDS":
			var seconds: String = WowStrings.get_text("SECONDS_ABBR_P1")
			return WowStrings.get_text("DUEL_OUTOFBOUNDS_TIMER") % [DUEL_FORFEIT_SECONDS, seconds]
		"SMSG_AUCTION_BIDDER_NOTIFICATION":
			reader.skip(16)
			var won: bool = reader.u32() == 0
			reader.u32()
			return _item_line("ERR_AUCTION_WON_S" if won else "ERR_AUCTION_OUTBID_S", reader.u32())
		"SMSG_AUCTION_OWNER_NOTIFICATION":
			reader.u32()
			var sold: bool = reader.u32() != 0
			reader.skip(12)
			return _item_line("ERR_AUCTION_SOLD_S" if sold else "ERR_AUCTION_EXPIRED_S", reader.u32())
		"SMSG_AUCTION_REMOVED_NOTIFICATION":
			reader.u32()
			return _item_line("ERR_AUCTION_REMOVED_S", reader.u32())
		"MSG_RANDOM_ROLL":
			var low: int = reader.u32()
			var high: int = reader.u32()
			var roll: int = reader.u32()
			var roller: String = WowClient.session.get_object_name(reader.u64())
			return WowStrings.format(WowStrings.get_text("RANDOM_ROLL_RESULT"), [roller, roll, low, high])
		"SMSG_QUESTUPDATE_ADD_ITEM":
			var entry: int = reader.u32()
			var item: String = WowClient.session.get_item_info(entry).get("name", "")
			return WowStrings.format(WowStrings.get_text("ERR_QUEST_ADD_ITEM_SII", "%s: +%d"), [item, reader.u32()])
		"SMSG_AREA_SPIRIT_HEALER_TIME":
			reader.u64()
			@warning_ignore("integer_division")
			var seconds: int = reader.u32() / 1000
			return WowStrings.format(WowStrings.get_text("AREA_SPIRIT_HEAL"), [seconds])
		"SMSG_RECEIVED_MAIL":
			return WowStrings.get_text("HAVE_MAIL", "You have unread mail")
		"SMSG_MEETINGSTONE_SETQUEUE":
			var area: int = reader.u32()
			var status: int = reader.u8()
			meeting_stone_area = 0 if status in [0, 3] else area
			var key: String = MEETING_STONE_STATUS.get(status, "")
			return WowStrings.format(WowStrings.get_text(key), [AreaInfo.area_name(area)]) if key else ""
		"SMSG_MEETINGSTONE_COMPLETE":
			meeting_stone_area = 0
			return WowStrings.get_text("ERR_MEETING_STONE_SUCCESS")
		"SMSG_MEETINGSTONE_IN_PROGRESS":
			return WowStrings.get_text("ERR_MEETING_STONE_IN_PROGRESS")
		"SMSG_MEETINGSTONE_MEMBER_ADDED":
			var added: String = WowClient.session.get_object_name(reader.u64())
			return WowStrings.format(WowStrings.get_text("ERR_MEETING_STONE_MEMBER_ADDED_S"), [added])
		"SMSG_GMTICKET_CREATE", "SMSG_GMTICKET_UPDATETEXT":
			return WowStrings.get_text(TICKET_ANSWERS.get(reader.u32(), "ERR_TICKET_CREATE_ERROR"))
		"SMSG_GMTICKET_DELETETICKET":
			return WowStrings.get_text("GM_TICKET_DELETED", "Your GM ticket was deleted.")
		"SMSG_GMTICKET_GETTICKET":
			if reader.u32() != TICKET_HAS_TEXT:
				return WowStrings.get_text("GM_TICKET_NONE", "You have no open GM ticket.")
			return "%s %s" % [WowStrings.get_text("TICKET_STATUS1"), reader.cstring()]
		"SMSG_INSTANCE_RESET":
			var text: String = WowStrings.get_text("INSTANCE_RESET_SUCCESS")
			return WowStrings.format(text, [map_name(reader.u32())])
		"SMSG_INSTANCE_RESET_FAILED":
			var key: String = RESET_FAILURES.get(reader.u32(), "INSTANCE_RESET_FAILED")
			return WowStrings.format(WowStrings.get_text(key), [map_name(reader.u32())])
		"SMSG_RAID_INSTANCE_MESSAGE":
			var key: String = RAID_MESSAGES.get(reader.u32(), "")
			var map: String = map_name(reader.u32())
			var seconds: int = reader.u32()
			if key == "RAID_INSTANCE_WELCOME":
				@warning_ignore("integer_division")
				var left: Array = [map, seconds / 86400, seconds / 3600 % 24, seconds / 60 % 60]
				return WowStrings.format(WowStrings.get_text(key), left)
			@warning_ignore("integer_division")
			var amount: int = seconds / 3600 if key.ends_with("HOURS") else seconds / 60
			return WowStrings.format(WowStrings.get_text(key), [map, amount]) if key else ""
	return ""


# The red error line a server message raises, or nothing.
static func error(opcode: String, payload: PackedByteArray) -> String:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_AREA_TRIGGER_MESSAGE":
			return reader.text(reader.u32())
		"SMSG_QUESTLOG_FULL":
			return WowStrings.get_text("ERR_QUEST_LOG_FULL")
		"SMSG_QUESTGIVER_QUEST_INVALID":
			return WowStrings.get_text(QUEST_FAILURES.get(reader.u32(), "ERR_QUEST_FAILED_LOW_LEVEL"))
		"SMSG_QUESTGIVER_QUEST_FAILED":
			reader.u32()
			return WowStrings.get_text(QUEST_FAILURES.get(reader.u32(), "ERR_QUEST_FAILED_INVENTORY_FULL"))
		"SMSG_QUESTUPDATE_FAILED", "SMSG_QUESTUPDATE_FAILEDTIMER":
			var title: String = WowClient.session.get_quest_info(reader.u32()).get("title", "")
			return WowStrings.format(WowStrings.get_text("ERR_QUEST_FAILED_S"), [title])
		"SMSG_FEIGN_DEATH_RESISTED":
			return WowStrings.get_text("ERR_FEIGN_DEATH_RESISTED")
		"SMSG_DISPEL_FAILED":
			return WowStrings.get_text("ERR_DISPEL_FAILED", "Dispel failed")
		"SMSG_PET_TAME_FAILURE":
			return WowStrings.get_text(PET_TAME_FAILURES.get(reader.u8(), "PETTAME_UNKNOWNERROR"))
		"SMSG_PET_BROKEN":
			return WowStrings.get_text("ERR_PET_BROKEN")
		"SMSG_MEETINGSTONE_JOINFAILED":
			return WowStrings.get_text(MEETING_STONE_FAILURES.get(reader.u8(), "ERR_MEETING_STONE_INVALID_LEVEL"))
		"SMSG_RAID_GROUP_ONLY":
			return WowStrings.get_text("ERR_RAID_GROUP_ONLY")
		"SMSG_FISH_ESCAPED":
			return WowStrings.get_text("ERR_FISH_ESCAPED")
		"SMSG_FISH_NOT_HOOKED":
			return WowStrings.get_text("ERR_FISH_NOT_HOOKED")
	return ""


# Sounds, music and cinematics the server starts; true when the opcode was one of them.
static func play(opcode: String, payload: PackedByteArray) -> bool:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_PLAY_SOUND", "SMSG_PLAY_OBJECT_SOUND":
			WowAssets.audio.play_entry(reader.u32())
		"SMSG_PLAY_MUSIC":
			WowAssets.audio.play_music_entry(reader.u32())
		"SMSG_TRIGGER_CINEMATIC":
			# ponytail: the flyover is not drawn, only acknowledged so the server moves on.
			WowClient.session.send_packet("CMSG_NEXT_CINEMATIC_CAMERA", [])
			WowClient.session.send_packet("CMSG_COMPLETE_CINEMATIC", [])
		_:
			return false
	return true


static func map_name(map_id: int) -> String:
	if _maps == null:
		_maps = WowDBC.open(WowAssets.archive, "Map")
	var row: int = _maps.find(map_id)
	return _maps.get_string(row, "MapName") if row >= 0 else ""


# SMSG_RAID_INSTANCE_INFO: each saved raid's map, seconds until it resets, and instance id.
static func raid_lockouts(payload: PackedByteArray) -> PackedStringArray:
	var reader: PacketReader = PacketReader.new(payload)
	var lines: PackedStringArray = []
	for i: int in reader.u32():
		var map: String = map_name(reader.u32())
		var seconds: int = reader.u32()
		var instance: int = reader.u32()
		@warning_ignore("integer_division")
		var left: String = "%dd %dh %dm" % [seconds / 86400, seconds / 3600 % 24, seconds / 60 % 60]
		lines.append("%s (%d): %s" % [map, instance, left])
	if lines.is_empty():
		lines.append(WowStrings.get_text("NO_RAID_INSTANCES_SAVED", "You are not saved to any raids."))
	return lines


# SMSG_WHO: shown and matched counts, then name, guild, level, class, race and zone per player.
static func who_rows(payload: PackedByteArray) -> Dictionary:
	var reader: PacketReader = PacketReader.new(payload)
	var shown: int = reader.u32()
	var total: int = reader.u32()
	var rows: Array[Dictionary] = []
	for i: int in shown:
		rows.append({
			"name": reader.cstring(),
			"guild": reader.cstring(),
			"level": reader.u32(),
			"class": CharacterOptions.class_label(reader.u32()),
			"race": CharacterOptions.race_name(reader.u32()),
			"zone": AreaInfo.area_name(reader.u32()),
		})
	return {"rows": rows, "total": total}


static func who_lines(payload: PackedByteArray) -> PackedStringArray:
	var answer: Dictionary = who_rows(payload)
	var lines: PackedStringArray = []
	for found: Dictionary in answer["rows"]:
		var args: Array = [
			found["name"], found["name"], found["level"], found["race"], found["class"],
			found["zone"],
		]
		if not found["guild"].is_empty():
			args.insert(5, found["guild"])
		var key: String = "WHO_LIST_FORMAT" if found["guild"].is_empty() else "WHO_LIST_GUILD_FORMAT"
		lines.append(WowStrings.format(WowStrings.get_text(key), args))
	lines.append(WowStrings.format(WowStrings.get_text("WHO_NUM_RESULTS"), [answer["total"]]))
	return lines


# CMSG_GMTICKET_CREATE: category, map, position, the text and a reserved string.
static func open_ticket(text: String, map_id: int, wow_position: Vector3) -> void:
	var payload: PackedByteArray = []
	payload.resize(17)
	payload.encode_u8(0, TICKET_CATEGORY_GAMEPLAY)
	payload.encode_u32(1, map_id)
	payload.encode_float(5, wow_position.x)
	payload.encode_float(9, wow_position.y)
	payload.encode_float(13, wow_position.z)
	payload.append_array(text.to_utf8_buffer())
	payload.append_array([0, 0])
	WowClient.session.send_packet("CMSG_GMTICKET_CREATE", payload)


# CMSG_WHO: any level, race and class, no zones, and the words to match names, guilds and zones by.
static func ask_who(words: PackedStringArray) -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u32(4, 100)
	payload.append_array([0, 0, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0])
	var count: PackedByteArray = [0, 0, 0, 0]
	count.encode_u32(0, words.size())
	payload.append_array(count)
	for word: String in words:
		payload.append_array(word.to_utf8_buffer())
		payload.append(0)
	WowClient.session.send_packet("CMSG_WHO", payload)


static func _played(seconds: int) -> String:
	@warning_ignore("integer_division")
	var parts: Array = [seconds / 86400, seconds / 3600 % 24, seconds / 60 % 60, seconds % 60]
	return WowStrings.format(WowStrings.get_text("TIME_DAYHOURMINUTESECOND"), parts)


static func _item_line(key: String, entry: int) -> String:
	var item_name: String = WowClient.session.get_item_info(entry).get("name", "")
	return WowStrings.format(WowStrings.get_text(key), [item_name])
