class_name AreaInfo
extends RefCounted

enum FactionGroup { NONE = 0, ALLIANCE = 2, HORDE = 4 }

const HORDE_RACES: Array[int] = [2, 5, 6, 8]

static var _areas: WowDBC


static func area_name(area_id: int) -> String:
	var row: int = _row(area_id)
	return _areas.get_string(row, "Name") if row >= 0 else ""


# Subzones carry no faction of their own, so the owning zone's answers for them.
static func faction_group(area_id: int) -> FactionGroup:
	var row: int = _row(area_id)
	while row >= 0:
		var group: int = _areas.get_uint(row, "FactionGroup")
		if group != 0:
			return group as FactionGroup
		var parent: int = _areas.get_uint(row, "ParentAreaNum")
		row = _row(parent) if parent != 0 else -1
	return FactionGroup.NONE


static func zone_of(area_id: int) -> int:
	var row: int = _row(area_id)
	var parent: int = _areas.get_uint(row, "ParentAreaNum") if row >= 0 else 0
	return zone_of(parent) if parent != 0 else area_id


static func flags(area_id: int) -> int:
	var row: int = _row(area_id)
	return _areas.get_uint(row, "Flags") if row >= 0 else 0


static func player_group(race: int) -> FactionGroup:
	return FactionGroup.HORDE if race in HORDE_RACES else FactionGroup.ALLIANCE


static func _row(area_id: int) -> int:
	if _areas == null:
		_areas = WowDBC.open(WowAssets.archive, "AreaTable")
	return _areas.find(area_id)
