class_name WorldStateScoreFrame
extends Control

signal close_requested
signal open_requested

# The tabs in order; stock numbers the factions the other way round from the wire.
enum Team { ALL, ALLIANCE, HORDE }

const ROWS: int = 22
const STAT_COLUMNS: int = 7
# WorldStateUI.dbc: kind 2 rows are this map's scoreboard columns, in table order.
const MAP_COLUMN: int = 1
const ICON_COLUMN: int = 4
const TEXT_COLUMN: int = 5
const KIND_COLUMN: int = 40
const SCOREBOARD: int = 2
const ANY_MAP: int = 0xFFFFFFFF
# WorldStateScoreFrame_Resize: the window widens by a fixed step per battleground column.
const BASE_WIDTH: float = 530.0
const SCROLL_BAR_WIDTH: float = 37.0
const COLUMN_SPACING: float = 77.0
const HONOR_GAP: float = 58.0
const HEADERS: Dictionary[String, String] = {
	"KB": "SCORE_KILLING_BLOWS", "Deaths": "DEATHS", "HK": "SCORE_HONORABLE_KILLS",
	"DamageDone": "SCORE_DAMAGE_DONE", "HealingDone": "SCORE_HEALING_DONE", "Team": "TEAM",
	"TeamSkill": "SCORE_TEAM_SKILL",
}
# Each fixed header and the row label that sits under it.
const ROW_LABELS: Dictionary[String, String] = {
	"KB": "KillingBlows", "Deaths": "Deaths", "HK": "HonorableKills",
	"DamageDone": "Damage", "HealingDone": "Healing", "HonorGained": "HonorGained",
	"TeamSkill": "TeamSkill",
}
# WorldStateScoreFrame_Update's arena colors: Green team then Gold, for the banners and the names.
const ARENA_STRIP_COLORS: Array[Color] = [Color(0.19, 0.57, 0.11), Color(0.85, 0.71, 0.26)]
const ARENA_NAME_COLORS: Array[Color] = [Color(0.1, 1.0, 0.1), Color(1.0, 0.82, 0.0)]
const COLUMN_SPACING_STOCK: float = 76.0
# WorldStateScoreFrame_Resize's stat column counts: a battleground, a skirmish, a rated arena.
const BATTLEGROUND_COLUMNS: int = 7
const SKIRMISH_COLUMNS: int = 4
const RATED_COLUMNS: int = 6
const SKIRMISH_EXTRA_WIDTH: float = 43.0
const HORDE_COLOR: Color = Color(1.0, 0.1, 0.1)
const ALLIANCE_COLOR: Color = Color(0.0, 0.68, 0.94)
const OWN_COLOR: Color = Color(1.0, 0.82, 0.0)
# UI-PVP-Banner strips as texture fractions: left then right, Alliance then Horde.
const STRIPS: Array[Rect2] = [
	Rect2(0.0, 0.0, 1.0, 0.25), Rect2(0.0, 0.25, 0.97265625, 0.25),
	Rect2(0.0, 0.5, 1.0, 0.25), Rect2(0.0, 0.75, 0.97265625, 0.25),
]

var _table: WowDBC
var _map_id: int = -1
var _team: Team = Team.ALL
var _offset: int = 0
var _rows: Array[Dictionary] = []
var _columns: Array[Dictionary] = []
var _strips: Array[AtlasTexture] = []
var _kb_x: float = 0.0

@onready var _scroll: WowScrollFrame = %WorldStateScoreScrollFrame


func _ready() -> void:
	_table = WowDBC.open(WowAssets.archive, "WorldStateUI")
	var banner: Texture2D = (%WorldStateScoreButton1FactionLeft as TextureRect).texture
	for fraction: Rect2 in STRIPS:
		var strip: AtlasTexture = AtlasTexture.new()
		strip.atlas = banner
		var extent: Vector2 = banner.get_size()
		strip.region = Rect2(fraction.position * extent, fraction.size * extent)
		_strips.append(strip)
	for header: String in HEADERS:
		var title: Label = get_node("%%WorldStateScoreFrame%sText" % header)
		title.text = WowStrings.get_text(HEADERS[header])
	_kb_x = (%WorldStateScoreFrameKB as Control).position.x
	for team: Team in Team.values():
		_tab(team).pressed.connect(_on_tab_pressed.bind(team))
	_scroll.faux = true
	_scroll.scrolled.connect(_on_scrolled)
	%WorldStateScoreFrameCloseButton.pressed.connect(close_requested.emit)
	%WorldStateScoreFrameLeaveButton.pressed.connect(_on_leave_pressed)
	WowClient.battlegrounds.scores_changed.connect(_on_scores_changed)
	WowClient.session.name_received.connect(func(_guid: int, _name: String) -> void: refresh())
	visibility_changed.connect(_on_visibility_changed)
	hide()


func show_map(map_id: int) -> void:
	if map_id == _map_id:
		return
	_map_id = map_id
	_columns.clear()
	for row: int in _table.row_count():
		var here: bool = _table.get_uint(row, MAP_COLUMN) in [map_id, ANY_MAP]
		if here and _table.get_uint(row, KIND_COLUMN) == SCOREBOARD:
			_columns.append({
				"text": _table.get_string(row, TEXT_COLUMN),
				"icon": _table.get_string(row, ICON_COLUMN),
			})
		elif not _columns.is_empty():
			break


func refresh() -> void:
	if not is_visible_in_tree():
		return
	var battlegrounds: Battlegrounds = WowClient.battlegrounds
	var ended: bool = battlegrounds.winner != Battlegrounds.Winner.NONE
	var arena: bool = battlegrounds.arena
	%WorldStateScoreWinnerFrame.visible = ended
	%WorldStateScoreFrameLeaveButton.visible = ended
	%WorldStateScoreFrameTimerLabel.visible = false
	%WorldStateScoreFrameTimer.visible = false
	if ended:
		_show_winner(battlegrounds)
	for team: Team in Team.values():
		_tab(team).visible = not arena
	%WorldStateScoreFrameDeaths.visible = not arena
	%WorldStateScoreFrameHK.visible = not arena
	%WorldStateScoreFrameTeam.visible = _rated()
	%WorldStateScoreFrameTeamSkill.visible = _rated()
	%WorldStateScoreFrameHonorGained.visible = not arena or _rated()
	(%WorldStateScoreFrameHonorGainedText as Label).text = \
			WowStrings.get_text("SCORE_RATING_CHANGE" if arena else "SCORE_HONOR_GAINED")
	_place_columns()
	_rows = battlegrounds.scores.filter(_on_team)
	_scroll.visible = _rows.size() > ROWS
	_scroll.set_range(maxi(_rows.size() - ROWS, 0))
	for i: int in STAT_COLUMNS:
		var header: Control = get_node("%%WorldStateScoreColumn%d" % (i + 1))
		header.visible = i < _columns.size()
		if header.visible:
			var title: Label = get_node("%%WorldStateScoreColumn%dText" % (i + 1))
			title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			title.text = _columns[i]["text"]
	_resize()
	for i: int in ROWS:
		_fill_row(i)
	_count_players(battlegrounds.scores)


func _fill_row(i: int) -> void:
	var stem: String = "%%WorldStateScoreButton%d" % (i + 1)
	var row: Control = get_node(stem)
	var index: int = i + _offset
	row.visible = index < _rows.size()
	if not row.visible:
		return
	var score: Dictionary = _rows[index]
	var guid: int = score["guid"]
	var alliance: bool = _is_alliance(score)
	var rank: int = score["rank"]
	var badge: TextureRect = get_node(stem + "RankButtonIcon")
	badge.visible = rank > 0
	if rank > 0:
		badge.texture = _art("Interface\\PvPRankBadges\\PvPRank%02d" % rank)
	var player_name: Label = get_node(stem + "NameButtonName")
	player_name.text = WowClient.session.get_object_name(guid)
	player_name.modulate = ALLIANCE_COLOR if alliance else HORDE_COLOR
	if guid == WowClient.session.get_player_guid():
		player_name.modulate = OWN_COLOR
	(get_node(stem + "KillingBlows") as Label).text = str(score["killing_blows"])
	(get_node(stem + "Damage") as Label).text = str(score.get("damage", 0))
	(get_node(stem + "Healing") as Label).text = str(score.get("healing", 0))
	_set_strips(get_node(stem + "FactionLeft"), get_node(stem + "FactionRight"), alliance)
	if score.has("team"):
		_fill_arena_row(stem, score)
	else:
		(get_node(stem + "HonorableKills") as Label).text = str(score["honorable_kills"])
		(get_node(stem + "Deaths") as Label).text = str(score["deaths"])
		(get_node(stem + "HonorGained") as Label).text = str(score["honor"])
		for part: String in ["HonorableKills", "Deaths", "HonorGained"]:
			(get_node(stem + part) as Control).show()
		for part: String in ["Team", "TeamSkill"]:
			(get_node(stem + part) as Control).hide()
		for part: String in ["FactionLeft", "FactionRight"]:
			(get_node(stem + part) as CanvasItem).self_modulate = Color.WHITE
	var stats: PackedInt32Array = score["stats"]
	for column: int in STAT_COLUMNS:
		_fill_stat(stem + "Column%d" % (column + 1), column, stats, alliance)
	for header: String in ROW_LABELS:
		_center_under(get_node(stem + ROW_LABELS[header]), "%%WorldStateScoreFrame%s" % header)
	var team_name: Label = get_node(stem + "Team")
	team_name.position.x = (%WorldStateScoreFrameTeam as Control).position.x - row.position.x
	for column: int in _columns.size():
		var under: String = "%%WorldStateScoreColumn%d" % (column + 1)
		var count: Label = get_node(stem + "Column%dText" % (column + 1))
		_center_under(count, under)
		var flag: Control = get_node(stem + "Column%dIcon" % (column + 1))
		flag.position.x = count.position.x - flag.size.x


# A column with an icon counts flags as "x 2" beside it; a plain one prints the number.
func _fill_stat(stem: String, column: int, stats: PackedInt32Array, alliance: bool) -> void:
	var text: Label = get_node(stem + "Text")
	var icon: TextureRect = get_node(stem + "Icon")
	text.visible = column < _columns.size()
	icon.visible = false
	if not text.visible:
		return
	var value: int = stats[column] if column < stats.size() else 0
	var art: String = _columns[column]["icon"]
	if art.is_empty():
		text.text = str(value)
		return
	text.text = WowStrings.get_text("FLAG_COUNT_TEMPLATE") % value if value > 0 else ""
	icon.visible = value > 0
	if icon.visible:
		icon.texture = _art(art + ("1" if alliance else "0"))


# The arena rows' team, matchmaking and rating change, and their Green or Gold coloring.
func _fill_arena_row(stem: String, score: Dictionary) -> void:
	var team: int = clampi(score["team"], 0, 1)
	var info: Dictionary = WowClient.battlegrounds.arena_teams[team]
	var rated: bool = _rated()
	(get_node(stem + "NameButtonName") as Label).modulate = ARENA_NAME_COLORS[team]
	for part: String in ["FactionLeft", "FactionRight"]:
		(get_node(stem + part) as CanvasItem).self_modulate = ARENA_STRIP_COLORS[team]
	(get_node(stem + "HonorableKills") as Control).hide()
	(get_node(stem + "Deaths") as Control).hide()
	for part: String in ["Team", "TeamSkill", "HonorGained"]:
		(get_node(stem + part) as Control).visible = rated
	(get_node(stem + "Team") as Label).text = info["name"]
	(get_node(stem + "TeamSkill") as Label).text = str(info["matchmaking"])
	(get_node(stem + "HonorGained") as Label).text = str(info["rating_change"])


func _show_winner(battlegrounds: Battlegrounds) -> void:
	var winner: int = battlegrounds.winner
	var text: Label = %WorldStateScoreWinnerFrameText
	var left: TextureRect = %WorldStateScoreWinnerFrameLeft
	var right: TextureRect = %WorldStateScoreWinnerFrameRight
	if not battlegrounds.arena:
		var alliance_won: bool = winner == Battlegrounds.Winner.ALLIANCE
		text.text = WowStrings.get_text("VICTORY_TEXT%d" % winner)
		text.modulate = ALLIANCE_COLOR if alliance_won else HORDE_COLOR
		_set_strips(left, right, alliance_won)
		left.self_modulate = Color.WHITE
		right.self_modulate = Color.WHITE
		return
	var team_name: String = battlegrounds.arena_teams[winner]["name"] if winner < 2 else ""
	text.text = WowStrings.get_text("VICTORY_TEXT_ARENA%d" % winner)
	if _rated():
		text.text = WowStrings.get_text("VICTORY_TEXT_ARENA_WINS") % team_name \
				if not team_name.is_empty() else WowStrings.get_text("VICTORY_TEXT_ARENA_DRAW")
	text.modulate = ARENA_NAME_COLORS[clampi(winner, 0, 1)]
	_set_strips(left, right, true)
	left.self_modulate = ARENA_STRIP_COLORS[clampi(winner, 0, 1)]
	right.self_modulate = left.self_modulate


# WorldStateScoreFrame_Update's reanchoring: an arena drops the kill and death columns.
func _place_columns() -> void:
	var arena: bool = WowClient.battlegrounds.arena
	var team: Control = %WorldStateScoreFrameTeam
	var kb: Control = %WorldStateScoreFrameKB
	kb.position.x = team.position.x + team.size.x - 10.0 if _rated() else _kb_x
	var damage: Control = %WorldStateScoreFrameDamageDone
	var before: Control = kb if arena else %WorldStateScoreFrameHK
	damage.position.x = before.position.x + before.size.x - 5.0
	var healing: Control = %WorldStateScoreFrameHealingDone
	healing.position.x = damage.position.x + damage.size.x - 5.0
	var skill: Control = %WorldStateScoreFrameTeamSkill
	skill.position.x = healing.position.x + healing.size.x + 10.0


func _rated() -> bool:
	var teams: Array[Dictionary] = WowClient.battlegrounds.arena_teams
	return not teams.is_empty() and not String(teams[0]["name"]).is_empty()


func _resize() -> void:
	var width: float = BASE_WIDTH + _columns.size() * COLUMN_SPACING
	if WowClient.battlegrounds.arena:
		var columns: int = RATED_COLUMNS if _rated() else SKIRMISH_COLUMNS
		width += (columns - BATTLEGROUND_COLUMNS) * COLUMN_SPACING_STOCK
		width += (%WorldStateScoreFrameTeam as Control).size.x if _rated() else SKIRMISH_EXTRA_WIDTH
	if _scroll.visible:
		width += SCROLL_BAR_WIDTH
	size.x = width
	(%WorldStateScoreFrameTopBackground as Control).size.x = width - 129.0
	var row_width: float = width - (165.0 if _scroll.visible else 137.0)
	_scroll.size.x = width - 165.0
	for i: int in ROWS:
		(get_node("%%WorldStateScoreButton%d" % (i + 1)) as Control).size.x = row_width
	var honor: Control = %WorldStateScoreFrameHonorGained
	if WowClient.battlegrounds.arena:
		var skill: Control = %WorldStateScoreFrameTeamSkill
		honor.position.x = skill.position.x + skill.size.x + 5.0
		return
	var last: Control = %WorldStateScoreFrameHK
	if not _columns.is_empty():
		last = get_node("%%WorldStateScoreColumn%d" % _columns.size())
	honor.position.x = last.position.x + last.size.x / 2.0 + HONOR_GAP - honor.size.x / 2.0


# Rows and headers both hang off the frame, so the row's own offset is all that separates them.
func _center_under(label: Label, header_path: String) -> void:
	var header: Control = get_node(header_path)
	var row: Control = label.get_parent()
	label.size.x = label.get_minimum_size().x
	label.position.x = header.position.x + header.size.x / 2.0 - row.position.x - label.size.x / 2.0


func _art(file: String) -> WowTexture:
	var art: WowTexture = WowTexture.new()
	art.file = file + ".blp"
	return art


func _set_strips(left: TextureRect, right: TextureRect, alliance: bool) -> void:
	left.texture = _strips[0 if alliance else 2]
	right.texture = _strips[1 if alliance else 3]


func _count_players(scores: Array[Dictionary]) -> void:
	var alliance: int = scores.filter(_is_alliance).size()
	var horde: int = scores.size() - alliance
	var parts: PackedStringArray = []
	if alliance > 0:
		parts.append(_plural("PLAYER_COUNT_ALLIANCE", alliance))
	if horde > 0:
		parts.append(_plural("PLAYER_COUNT_HORDE", horde))
	var count: Label = %WorldStateScorePlayerCount
	count.visible = not WowClient.battlegrounds.arena
	count.text = " / ".join(parts)
	var last: Control = get_node("%%WorldStateScoreButton%d" % clampi(_rows.size() - _offset, 1, ROWS))
	count.position = last.position + Vector2(15.0, last.size.y + 6.0)


func _plural(key: String, count: int) -> String:
	return WowStrings.get_text(key + ("_P1" if count != 1 else "")) % count


# An arena row is Gold (1) or Green by its team byte; a battleground row goes by race.
func _is_alliance(score: Dictionary) -> bool:
	if score.has("team"):
		return score["team"] == 1
	var race: int = WowClient.session.get_player_race(score["guid"])
	return CharacterOptions.faction(race) == CharacterOptions.Faction.ALLIANCE


func _on_team(score: Dictionary) -> bool:
	return _team == Team.ALL or (_team == Team.ALLIANCE) == _is_alliance(score)


func _tab(team: Team) -> Control:
	return get_node("%%WorldStateScoreFrameTab%d" % (team + 1))


func _on_tab_pressed(team: Team) -> void:
	_team = team
	_offset = 0
	for other: Team in Team.values():
		PanelManager.select_tab(_tab(other), other == team)
	var label: Label = get_node("%%WorldStateScoreFrameTab%dText" % (team + 1))
	%WorldStateScoreFrameLabel.text = WowStrings.get_text("STAT_TEMPLATE") % label.text
	WowAssets.audio.play_sound("igCharacterInfoTab")
	refresh()


func _on_scrolled(value: float) -> void:
	if roundi(value) != _offset:
		_offset = roundi(value)
		refresh()


func _on_scores_changed() -> void:
	if WowClient.battlegrounds.winner != Battlegrounds.Winner.NONE:
		open_requested.emit()
	refresh()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		if WowClient.battlegrounds.in_battle():
			WowClient.battlegrounds.request_scores()
		refresh()


func _on_leave_pressed() -> void:
	WowClient.battlegrounds.leave(_map_id)
	close_requested.emit()
