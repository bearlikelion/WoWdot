class_name PVPBattlegroundFrame
extends Control

signal close_requested

const SHOWN: int = 5
const BATTLEGROUND_INSTANCE: int = 3
const RANDOM_BATTLEGROUND: int = 32
const PARTY_SIZE: int = 5
# PVPBATTLEGROUND_TEXTURELIST: each battleground type's art behind the list.
const TEXTURES: Dictionary[int, String] = {
	1: "Interface\\PVPFrame\\PvpBg-AlteracValley.blp",
	2: "Interface\\PVPFrame\\PvpBg-WarsongGulch.blp",
	3: "Interface\\PVPFrame\\PvpBg-ArathiBasin.blp",
	7: "Interface\\PVPFrame\\PvpBg-EyeOfTheStorm.blp",
	9: "Interface\\PVPFrame\\PvpBg-StrandOfTheAncients.blp",
	30: "Interface\\PVPFrame\\PvpBg-IsleOfConquest.blp",
	32: "Interface\\PVPFrame\\PvpRandomBg.blp",
}
const REWARDS: String = "%PVPBattlegroundFrameInfoScrollFrameChildFrameRewardsInfo"

# The battlegrounds the character can queue for, as {id, name, map, group}.
var _types: Array[Dictionary] = []
var _selected: int = 0
var _offset: int = 0

@onready var _battlegrounds: Battlegrounds = WowClient.battlegrounds
@onready var _scroll: WowScrollFrame = %PVPBattlegroundFrameTypeScrollFrame


func _ready() -> void:
	for i: int in SHOWN:
		_row(i).pressed.connect(_on_row_pressed.bind(i))
	%PVPBattlegroundFrameJoinButton.pressed.connect(_join.bind(false))
	%PVPBattlegroundFrameGroupJoinButton.pressed.connect(_join.bind(true))
	%PVPBattlegroundFrameCancelButton.pressed.connect(close_requested.emit)
	%WintergraspTimer.hide()
	_scroll.faux = true
	_scroll.scrolled.connect(_on_scrolled)
	_battlegrounds.listed.connect(func(_map_id: int, _instances: PackedInt32Array) -> void:
		_show_info())
	visibility_changed.connect(_on_visibility_changed)


func _load_types() -> void:
	var session: WowSession = WowClient.session
	var level: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_LEVEL")
	var table: WowDBC = WowDBC.open(WowAssets.archive, "BattlemasterList")
	_types.clear()
	for row: int in table.row_count():
		if table.get_uint(row, "InstanceType") != BATTLEGROUND_INSTANCE \
		or level < table.get_uint(row, "MinLevel"):
			continue
		_types.append({
			"id": table.get_uint(row, "ID"),
			"name": table.get_string(row, "Name"),
			"map": table.get_int(row, "MapID"),
			"group": table.get_uint(row, "MaxGroupSize"),
		})


# PVPBattleground_UpdateBattlegrounds: the list, with the chosen one's highlight locked.
func _show_rows() -> void:
	for i: int in SHOWN:
		var row: WowButton = _row(i)
		var index: int = _offset + i
		row.visible = index < _types.size()
		if row.visible:
			var text: Label = get_node("%%BattlegroundType%dText" % (i + 1))
			text.text = _types[index]["name"]
			row.highlight_locked = _types[index]["id"] == _selected


# PVPBattleground_UpdateInfo: a random battleground shows its rewards, the rest their intro.
func _show_info() -> void:
	var chosen: Dictionary = _chosen()
	if chosen.is_empty():
		return
	var art: WowTexture = WowTexture.new()
	art.file = TEXTURES.get(chosen["id"], TEXTURES[RANDOM_BATTLEGROUND])
	%PVPBattlegroundFrameBGTex.texture = art
	var random: bool = chosen["id"] == RANDOM_BATTLEGROUND
	(get_node(REWARDS) as CanvasItem).visible = random
	%PVPBattlegroundFrameInfoScrollFrameChildFrameDescription.visible = not random
	if random:
		var rewards: Dictionary = _battlegrounds.rewards
		var amounts: Dictionary[String, int] = {
			"WinRewardHonorAmount": rewards.get("win_honor", 0),
			"WinRewardArenaAmount": rewards.get("win_arena", 0),
			"LossRewardHonorAmount": rewards.get("loss_honor", 0),
			"LossRewardArenaAmount": 0,
		}
		for part: String in amounts:
			(get_node(REWARDS + part) as Label).text = str(amounts[part])
	else:
		var maps: WowDBC = WowDBC.open(WowAssets.archive, "Map")
		var row: int = maps.find(chosen["map"])
		var session: WowSession = WowClient.session
		var bytes: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_BYTES_0")
		var race: int = bytes & 0xFF
		var column: String = "HordeDescription" if race in [2, 5, 6, 8, 10] \
				else "AllianceDescription"
		%PVPBattlegroundFrameInfoScrollFrameChildFrameDescription.text = \
				maps.get_string(row, column) if row >= 0 else ""
	%PVPBattlegroundFrameGroupJoinButtonText.text = WowStrings.get_text(
		"JOIN_AS_PARTY" if chosen["group"] == PARTY_SIZE else "JOIN_AS_GROUP"
	)


func _chosen() -> Dictionary:
	for entry: Dictionary in _types:
		if entry["id"] == _selected:
			return entry
	return {}


func _select(battleground_type: int) -> void:
	if _types.is_empty():
		return
	_selected = battleground_type
	_battlegrounds.request_list(battleground_type)
	_show_rows()
	_show_info()


func _row(index: int) -> WowButton:
	return get_node("%%BattlegroundType%d" % (index + 1))


func _join(as_group: bool) -> void:
	var chosen: Dictionary = _chosen()
	if not chosen.is_empty():
		_battlegrounds.join(0, chosen["map"], 0, as_group)


func _on_row_pressed(index: int) -> void:
	_select(_types[_offset + index]["id"])


func _on_scrolled(value: float) -> void:
	_offset = roundi(value)
	_show_rows()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	_load_types()
	_scroll.set_range(maxi(_types.size() - SHOWN, 0))
	if _chosen().is_empty() and not _types.is_empty():
		_selected = _types[0]["id"]
	_select(_selected)
