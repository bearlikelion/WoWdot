class_name QuestLog
extends RefCounted

enum State { ACTIVE, COMPLETE, FAILED }

const MAX_QUESTS: int = 20
# Each PLAYER_QUEST_LOG slot is the quest id, its counters and state, then its timer.
const SLOT_FIELDS: int = 3
const COUNTER_BITS: int = 6
const COUNTER_MASK: int = 0x3F
const STATE_SHIFT: int = 24
const OBJECTIVES: int = 4

static var _areas: WowDBC
static var _sorts: WowDBC


# The occupied quest log slots, in slot order.
static func slots() -> Array[int]:
	var taken: Array[int] = []
	for slot: int in MAX_QUESTS:
		if quest_id(slot):
			taken.append(slot)
	return taken


static func quest_id(slot: int) -> int:
	return _field(slot, 0)


static func state(slot: int) -> State:
	var bits: int = _field(slot, 1) >> STATE_SHIFT
	if bits & 2:
		return State.FAILED
	return State.COMPLETE if bits & 1 else State.ACTIVE


static func counter(slot: int, objective: int) -> int:
	return (_field(slot, 1) >> (objective * COUNTER_BITS)) & COUNTER_MASK


static func time_left(slot: int) -> int:
	return _field(slot, 2)


# The zone or category a quest files under, such as Dun Morogh or Class.
static func header(info: Dictionary) -> String:
	var zone_or_sort: int = info.get("zone_or_sort", 0)
	if zone_or_sort > 0:
		if _areas == null:
			_areas = WowDBC.open(WowAssets.archive, "AreaTable")
		var row: int = _areas.find(zone_or_sort)
		return _areas.get_text(row, "Name") if row >= 0 else ""
	if zone_or_sort < 0:
		if _sorts == null:
			_sorts = WowDBC.open(WowAssets.archive, "QuestSort")
		var row: int = _sorts.find(-zone_or_sort)
		return _sorts.get_text(row, "Name") if row >= 0 else ""
	return ""


# GetQuestLogLeaderBoard for every objective: [text, finished], or empty while names are queried.
static func objectives(slot: int, info: Dictionary) -> Array[Array]:
	var session: WowSession = WowClient.session
	var lines: Array[Array] = []
	var list: Array = info.get("objective_list", [])
	for i: int in list.size():
		var objective: Dictionary = list[i]
		var need: int = objective["target_count"]
		var target: int = objective["target"]
		if target != 0 and need > 0:
			var done: int = mini(counter(slot, i), need)
			var text: String = objective["text"]
			var line: String = ""
			if not text.is_empty():
				line = WowStrings.get_text("QUEST_OBJECTS_FOUND") % [text, done, need]
			elif target > 0:
				var creature: Dictionary = session.get_creature_template(target)
				line = WowStrings.get_text("QUEST_MONSTERS_KILLED") % [
					creature.get("name", ""), done, need,
				]
			else:
				var game_object: Dictionary = session.get_game_object_info(target & 0x7FFFFFFF)
				line = WowStrings.get_text("QUEST_OBJECTS_FOUND") % [
					game_object.get("name", ""), done, need,
				]
			lines.append([line, done >= need])
	for i: int in list.size():
		var objective: Dictionary = list[i]
		var item: int = objective["item"]
		var need: int = objective["item_count"]
		if item != 0 and need > 0:
			var have: int = mini(Inventory.item_count(item), need)
			var item_name: String = session.get_item_info(item).get("name", "")
			var line: String = WowStrings.get_text("QUEST_ITEMS_NEEDED") % [item_name, have, need]
			lines.append([line, have >= need])
	return lines


# The $N, $C, $R, $B and $G male:female; codes in quest text, filled in for the player.
static func format_text(text: String) -> String:
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	var bytes_0: int = session.get_field(guid, "UNIT_FIELD_BYTES_0")
	var female: bool = (bytes_0 >> 16) & 0xFF == 1
	var gender: RegEx = RegEx.create_from_string("\\$[Gg]\\s*([^:;]*):([^;]*);")
	text = gender.sub(text, "$2" if female else "$1", true)
	var player_name: String = session.get_object_name(guid)
	var race: String = CharacterOptions.race_name(bytes_0 & 0xFF)
	var player_class: String = CharacterOptions.class_label((bytes_0 >> 8) & 0xFF)
	return text.replace("$B", "\n").replace("$b", "\n") \
	.replace("$N", player_name).replace("$n", player_name) \
	.replace("$C", player_class).replace("$c", player_class.to_lower()) \
	.replace("$R", race).replace("$r", race.to_lower())


static func _field(slot: int, offset: int) -> int:
	var session: WowSession = WowClient.session
	var first: int = session.field_index("PLAYER_QUEST_LOG_1_1")
	return session.get_field(session.get_player_guid(), first + slot * SLOT_FIELDS + offset)
