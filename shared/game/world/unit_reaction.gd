class_name UnitReaction
extends RefCounted

enum Reaction { HOSTILE = 2, NEUTRAL = 4, FRIENDLY = 5 }

const COLORS: Dictionary[Reaction, Color] = {
	Reaction.HOSTILE: Color(1.0, 0.0, 0.0),
	Reaction.NEUTRAL: Color(1.0, 1.0, 0.0),
	Reaction.FRIENDLY: Color(0.0, 1.0, 0.0),
}
# QuestDifficultyColor, as GetDifficultyColor picks it from the level gap.
const IMPOSSIBLE: Color = Color(1.0, 0.1, 0.1)
const VERY_DIFFICULT: Color = Color(1.0, 0.5, 0.25)
const DIFFICULT: Color = Color(1.0, 1.0, 0.0)
const STANDARD: Color = Color(0.25, 0.75, 0.25)
const TRIVIAL: Color = Color(0.5, 0.5, 0.5)

static var _templates: WowDBC


# FactionTemplate rules: explicit enemy or friend factions first, then the group masks.
static func between(session: WowSession, from_guid: int, to_guid: int) -> Reaction:
	if _templates == null:
		_templates = WowDBC.open(WowAssets.archive, "FactionTemplate")
	var ours: int = _templates.find(session.get_field(from_guid, "UNIT_FIELD_FACTIONTEMPLATE"))
	var theirs: int = _templates.find(session.get_field(to_guid, "UNIT_FIELD_FACTIONTEMPLATE"))
	if ours < 0 or theirs < 0:
		return Reaction.NEUTRAL
	if _hostile(theirs, ours) or _hostile(ours, theirs):
		return Reaction.HOSTILE
	if _friendly(theirs, ours):
		return Reaction.FRIENDLY
	return Reaction.NEUTRAL


static func level_color(level: int, player_level: int) -> Color:
	var gap: int = level - player_level
	if gap >= 5:
		return IMPOSSIBLE
	if gap >= 3:
		return VERY_DIFFICULT
	if gap >= -2:
		return DIFFICULT
	if level > gray_level(player_level):
		return STANDARD
	return TRIVIAL


# The highest level that still counts as trivial (gray) for a player of this level.
static func gray_level(player_level: int) -> int:
	if player_level <= 5:
		return 0
	if player_level <= 39:
		return player_level - 5 - floori(player_level / 10.0)
	if player_level <= 59:
		return player_level - 1 - floori(player_level / 5.0)
	return player_level - 9


static func _hostile(row: int, other: int) -> bool:
	var other_faction: int = _templates.get_uint(other, "Faction")
	for i: int in 4:
		if _templates.get_uint(row, "Enemy%d" % i) == other_faction:
			return true
		if _templates.get_uint(row, "Friend%d" % i) == other_faction:
			return false
	return _templates.get_uint(row, "EnemyGroup") & _templates.get_uint(other, "FactionGroup") != 0


static func _friendly(row: int, other: int) -> bool:
	var other_faction: int = _templates.get_uint(other, "Faction")
	for i: int in 4:
		if _templates.get_uint(row, "Friend%d" % i) == other_faction:
			return true
	return _templates.get_uint(row, "FriendGroup") & _templates.get_uint(other, "FactionGroup") != 0 \
	or _templates.get_uint(other, "FriendGroup") & _templates.get_uint(row, "FactionGroup") != 0
