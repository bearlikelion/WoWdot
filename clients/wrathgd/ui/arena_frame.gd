class_name ArenaFrame
extends Control

signal close_requested
signal open_requested

# ArenaZone1 to 3 are the rated 2v2, 3v3 and 5v5 queues, and 4 to 6 the same as skirmishes.
const TEAM_SIZES: Array[int] = [2, 3, 5]
const ZONES: int = 6

var _selected: int = 0


func _ready() -> void:
	for i: int in ZONES:
		var zone: BaseButton = get_node("%%ArenaZone%d" % (i + 1))
		zone.pressed.connect(_on_zone_pressed.bind(i))
	%ArenaFrameJoinButton.pressed.connect(_join.bind(false))
	%ArenaFrameGroupJoinButton.pressed.connect(_join.bind(true))
	%ArenaFrameCancelButton.pressed.connect(close_requested.emit)
	%ArenaFrameCloseButton.pressed.connect(close_requested.emit)
	(%ArenaFrameZoneDescription as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	WowClient.battlegrounds.arena_listed.connect(_on_listed)


func set_portrait(texture: Texture2D) -> void:
	(%ArenaFramePortrait as TextureRect).texture = texture


# ArenaFrame_Update: only a party leader may queue rated, and alone only a skirmish.
func refresh() -> void:
	for i: int in ZONES:
		var team_size: int = TEAM_SIZES[i % TEAM_SIZES.size()]
		var casual: bool = i >= TEAM_SIZES.size()
		var kind: String = WowStrings.get_text("ARENA_CASUAL" if casual else "ARENA_RATED")
		(get_node("%%ArenaZone%dText" % (i + 1)) as Label).text = \
				WowStrings.get_text("PVP_TEAMTYPE") % [team_size, team_size] + " " + kind
		(get_node("%%ArenaZone%d" % (i + 1)) as WowButton).highlight_locked = i == _selected
	var leads: bool = PartyFrame.in_party() \
			and PartyFrame.leader == WowClient.session.get_player_guid()
	(%ArenaFrameJoinButton as BaseButton).disabled = _selected < TEAM_SIZES.size()
	(%ArenaFrameGroupJoinButton as BaseButton).disabled = not leads


func _join(as_group: bool) -> void:
	var rated: bool = _selected < TEAM_SIZES.size()
	WowClient.battlegrounds.join_arena(_selected % TEAM_SIZES.size(), as_group, rated)
	close_requested.emit()


func _on_zone_pressed(index: int) -> void:
	_selected = index
	refresh()


# ponytail: no arena season check, so rated queues always offer; the server refuses off-season.
func _on_listed() -> void:
	var leads: bool = PartyFrame.in_party() \
			and PartyFrame.leader == WowClient.session.get_player_guid()
	if not leads and _selected < TEAM_SIZES.size():
		_selected = TEAM_SIZES.size()
	(%ArenaFrameZoneDescription as Label).text = WowStrings.get_text("ARENA_MASTER_TEXT")
	open_requested.emit()
	refresh()
