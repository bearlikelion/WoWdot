class_name PVPParentFrame
extends Control

signal close_requested

# PVPTeam_Update lists the teams by size, one button each.
const TEAM_SIZES: Array[int] = [2, 3, 5]
const TAB_OVERLAP: float = -16.0
const MEMBERS_SHOWN: int = 10
const LOW_PLAYED_PERCENT: int = 10
const BANNER: String = "Interface\\PVPFrame\\PVP-Banner-%d.blp"
const BANNER_BORDER: String = "Interface\\PVPFrame\\PVP-Banner-%d-Border-%d.blp"
const EMBLEM: String = "Interface\\PVPFrame\\Icons\\PVP-Banner-Emblem-%d.blp"
const FACTION_ICON: String = "Interface\\TargetingFrame\\UI-PVP-%s.blp"
const EMPTY_TEAM_ALPHA: float = 0.4
const EMPTY_STANDARD_ALPHA: float = 0.1
const CAPTAIN_COLOR: Color = Color(1.0, 0.82, 0.0)
const OFFLINE_COLOR: Color = Color(0.5, 0.5, 0.5)
const LOW_PLAYED_COLOR: Color = Color(1.0, 0.0, 0.0)
const PORTRAIT: PackedScene = preload("res://ui/unit_portrait.tscn")
const PORTRAIT_MASK: Shader = preload("res://ui/portrait.gdshader")
# The XML gaps between a text and what is anchored to its right edge.
const POINTS_GAP: float = 15.0
const ICON_GAP: float = 4.0
const TEAM_SIZE_GAP: float = 5.0
# Label to the player field it shows.
const COUNTS: Dictionary[String, String] = {
	"PVPHonorTodayHonor": "PLAYER_FIELD_TODAY_CONTRIBUTION",
	"PVPHonorYesterdayHonor": "PLAYER_FIELD_YESTERDAY_CONTRIBUTION",
	"PVPHonorLifetimeKills": "PLAYER_FIELD_LIFETIME_HONORBALE_KILLS",
	"PVPFrameHonorPoints": "PLAYER_FIELD_HONOR_CURRENCY",
	"PVPFrameArenaPoints": "PLAYER_FIELD_ARENA_CURRENCY",
}

var season: bool = false

# The team shown in PVPTeamDetails, or 0.
var _details_team: int = 0
# Each team button's arena team id, 0 for a size the player has no team of.
var _button_teams: Array[int] = [0, 0, 0]
var _portrait: UnitPortrait

@onready var _arena: ArenaTeams = WowClient.arena_teams


func _ready() -> void:
	for i: int in TEAM_SIZES.size():
		(get_node("%%PVPTeam%d" % (i + 1)) as BaseButton).pressed.connect(_on_team_pressed.bind(i))
	%PVPParentFrameCloseButton.pressed.connect(close_requested.emit)
	%PVPFrameToggleButton.pressed.connect(_toggle_season)
	%PVPTeamDetailsToggleButton.pressed.connect(_toggle_season)
	%PVPTeamDetailsCloseButton.pressed.connect(%PVPTeamDetails.hide)
	var tabs: Array[Control] = []
	for tab: int in [1, 2]:
		var button: BaseButton = get_node("%%PVPParentFrameTab%d" % tab)
		button.pressed.connect(show_tab.bind(tab))
		tabs.append(button)
	PanelManager.chain_tabs(tabs, TAB_OVERLAP)
	for i: int in TEAM_SIZES.size():
		var data: String = "%%PVPTeam%dData" % (i + 1)
		space_around(get_node(data + "_"), get_node(data + "Wins"), get_node(data + "Loss"))
	space_around(%PVPTeamDetails_, %PVPTeamDetailsWins, %PVPTeamDetailsLoss)
	%PVPBattlegroundFrame.close_requested.connect(close_requested.emit)
	%PVPFrameOffSeason.hide()
	%PVPTeamDetailsAddTeamMember.hide()
	%PVPDropDown.hide()
	_portrait = PORTRAIT.instantiate()
	add_child(_portrait)
	var mask: ShaderMaterial = ShaderMaterial.new()
	mask.shader = PORTRAIT_MASK
	%PVPFramePortrait.material = mask
	%PVPFramePortrait.texture = _portrait.get_texture()
	_arena.changed.connect(refresh)
	WowClient.session.object_updated.connect(_on_object_updated)
	visibility_changed.connect(_on_visibility_changed)


# PVPParentFrame's tabs: 1 is honor and arena teams, 2 the battleground queue.
func show_tab(tab: int) -> void:
	%PVPFrame.visible = tab == 1
	%PVPBattlegroundFrame.visible = tab == 2
	%PVPTeamDetails.hide()
	for other: int in [1, 2]:
		PanelManager.select_tab(get_node("%%PVPParentFrameTab%d" % other), other == tab)


func refresh() -> void:
	if not is_visible_in_tree():
		return
	_show_honor()
	_show_teams()
	if %PVPTeamDetails.visible:
		_show_details()


# PVPHonor_Update: today's and yesterday's kills share PLAYER_FIELD_KILLS, sixteen bits each.
func _show_honor() -> void:
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	var kills: int = session.get_field(guid, "PLAYER_FIELD_KILLS")
	%PVPHonorTodayKills.text = str(kills & 0xFFFF)
	%PVPHonorYesterdayKills.text = str((kills >> 16) & 0xFFFF)
	for label: String in COUNTS:
		(get_node("%" + label) as Label).text = str(session.get_field(guid, COUNTS[label]))
	var race: int = session.get_field(guid, "UNIT_FIELD_BYTES_0") & 0xFF
	var faction: WowTexture = WowTexture.new()
	faction.file = FACTION_ICON % ("Horde" if race in [2, 5, 6, 8, 10] else "Alliance")
	%PVPFrameHonorIcon.texture = faction
	for prefix: String in ["%PVPFrameHonor", "%PVPFrameArena"]:
		place_after(get_node(prefix + "Points"), get_node(prefix + "Label"), POINTS_GAP)
		place_after(get_node(prefix + "Icon"), get_node(prefix + "Points"), ICON_GAP)


func _show_teams() -> void:
	var infos: Dictionary[int, Dictionary] = {}
	for slot: int in ArenaTeams.SLOTS:
		var info: Dictionary = _arena.slot_info(slot)
		if not info.is_empty():
			infos[info[ArenaTeams.Info.TYPE]] = info
	for i: int in TEAM_SIZES.size():
		var team_size: int = TEAM_SIZES[i]
		var prefix: String = "%%PVPTeam%d" % (i + 1)
		var info: Dictionary = infos.get(team_size, {})
		var team_id: int = info.get(ArenaTeams.Info.ID, 0)
		_button_teams[i] = team_id
		var team: Dictionary = _arena.teams.get(team_id, {})
		if team_id and not team.has("name"):
			_arena.query(team_id)
		var shown: bool = team_id != 0 and team.has("name")
		(get_node(prefix) as CanvasItem).modulate.a = 1.0 if shown else EMPTY_TEAM_ALPHA
		(get_node(prefix + "Data") as CanvasItem).visible = shown
		var standard: CanvasItem = get_node(prefix + "Standard")
		standard.modulate.a = 1.0 if shown else EMPTY_STANDARD_ALPHA
		(get_node(prefix + "StandardBorder") as CanvasItem).visible = shown
		(get_node(prefix + "StandardEmblem") as CanvasItem).visible = shown
		var type_label: Label = get_node(prefix + "TeamType")
		type_label.visible = not shown
		type_label.text = WowStrings.get_text("PVP_TEAMSIZE") % [team_size, team_size]
		var banner: TextureRect = get_node(prefix + "StandardBanner")
		banner.texture = load_texture(BANNER % team_size)
		var background: int = team.get("background", 0xFFFFFF)
		banner.self_modulate = team_color(background) if shown else Color.WHITE
		if shown:
			_show_team_data(prefix, team_size, info, team)


func _show_team_data(prefix: String, team_size: int, info: Dictionary, team: Dictionary) -> void:
	var played: int = team.get("games_season" if season else "games_week", 0)
	var wins: int = team.get("wins_season" if season else "wins_week", 0)
	(get_node(prefix + "DataName") as Label).text = team["name"]
	(get_node(prefix + "DataRating") as Label).text = str(team.get("rating", 0))
	(get_node(prefix + "DataGames") as Label).text = str(played)
	(get_node(prefix + "DataWins") as Label).text = str(wins)
	(get_node(prefix + "DataLoss") as Label).text = str(played - wins)
	(get_node(prefix + "DataTypeLabel") as Label).text = \
			WowStrings.get_text("ARENA_THIS_SEASON" if season else "ARENA_THIS_WEEK")
	var played_label: Label = get_node(prefix + "DataPlayed")
	var played_caption: Label = get_node(prefix + "DataPlayedLabel")
	if season:
		played_label.text = str(info[ArenaTeams.Info.PERSONAL_RATING])
		played_label.self_modulate = Color.WHITE
		played_caption.text = WowStrings.get_text("PVP_YOUR_RATING")
	else:
		var mine: int = info[ArenaTeams.Info.GAMES_WEEK]
		var percent: int = floori(100.0 * mine / maxi(played, 1))
		played_label.text = "%d (%d%%)" % [mine, percent]
		played_label.self_modulate = \
				LOW_PLAYED_COLOR if percent < LOW_PLAYED_PERCENT else Color.WHITE
		played_caption.text = WowStrings.get_text("PLAYED")
	var border: TextureRect = get_node(prefix + "StandardBorder")
	border.texture = load_texture(BANNER_BORDER % [team_size, team["border"]])
	border.self_modulate = team_color(team["border_color"])
	var emblem: TextureRect = get_node(prefix + "StandardEmblem")
	emblem.texture = load_texture(EMBLEM % team["emblem"])
	emblem.self_modulate = team_color(team["emblem_color"])
	%PVPFrameToggleButtonText.text = WowStrings.get_text(
		"ARENA_THIS_WEEK_TOGGLE" if season else "ARENA_THIS_SEASON_TOGGLE"
	)


# PVPTeamDetails_Update: the team's totals and one row per member.
func _show_details() -> void:
	var team: Dictionary = _arena.teams.get(_details_team, {})
	var team_size: int = team.get("type", 0)
	var played: int = team.get("games_season" if season else "games_week", 0)
	var wins: int = team.get("wins_season" if season else "wins_week", 0)
	%PVPTeamDetailsName.text = team.get("name", "")
	%PVPTeamDetailsSize.text = WowStrings.get_text("PVP_TEAMSIZE") % [team_size, team_size]
	place_after(%PVPTeamDetailsSize, %PVPTeamDetailsName, TEAM_SIZE_GAP)
	%PVPTeamDetailsRank.text = str(team.get("rank", 0))
	%PVPTeamDetailsRating.text = str(team.get("rating", 0))
	%PVPTeamDetailsGames.text = str(played)
	%PVPTeamDetailsWins.text = str(wins)
	%PVPTeamDetailsLoss.text = str(played - wins)
	%PVPTeamDetailsStatsType.text = \
			WowStrings.get_text("ARENA_THIS_SEASON" if season else "ARENA_THIS_WEEK").to_upper()
	%PVPTeamDetailsToggleButtonText.text = WowStrings.get_text(
		"ARENA_THIS_WEEK_TOGGLE" if season else "ARENA_THIS_SEASON_TOGGLE"
	)
	var roster: Array = team.get("roster", [])
	for i: int in MEMBERS_SHOWN:
		var prefix: String = "%%PVPTeamDetailsButton%d" % (i + 1)
		var button: CanvasItem = get_node(prefix)
		button.visible = i < roster.size()
		if button.visible:
			_show_member(prefix, roster[i], played)


func _show_member(prefix: String, member: Dictionary, team_played: int) -> void:
	var played: int = member["games_season" if season else "games_week"]
	var wins: int = member["wins_season" if season else "wins_week"]
	var color: Color = OFFLINE_COLOR if not member["online"] \
			else CAPTAIN_COLOR if member["captain"] else Color.WHITE
	var texts: Dictionary[String, String] = {
		"NameText": member["name"],
		"ClassText": CharacterOptions.class_label(member["class"]),
		"PlayedText": str(played),
		"WinLossWin": str(wins),
		"WinLossLoss": str(played - wins),
		"RatingText": str(member["personal_rating"]),
	}
	for part: String in texts:
		var label: Label = get_node(prefix + part)
		label.text = texts[part]
		label.self_modulate = color
	if floori(100.0 * played / maxi(team_played, 1)) < LOW_PLAYED_PERCENT:
		(get_node(prefix + "PlayedText") as Label).self_modulate = LOW_PLAYED_COLOR


# A LEFT to RIGHT anchor on a FontString sized by its text, which the converter cannot measure.
static func place_after(node: Control, label: Label, gap: float) -> void:
	label.size.x = label.get_combined_minimum_size().x
	node.position.x = label.position.x + label.size.x + gap


# A " - " FontString between two numbers anchored to its sides, spaced once its text has a width.
static func space_around(separator: Label, left: Label, right: Label) -> void:
	var center: float = (separator.offset_left + separator.offset_right) / 2.0
	var half: float = separator.get_minimum_size().x / 2.0
	left.offset_left = center - half
	left.offset_right = center - half
	right.offset_left = center + half
	right.offset_right = center + half


static func load_texture(path: String) -> WowTexture:
	var texture: WowTexture = WowTexture.new()
	texture.file = path
	return texture


static func team_color(argb: int) -> Color:
	return Color8((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF)


func _toggle_season() -> void:
	season = not season
	refresh()


func _on_team_pressed(index: int) -> void:
	if _button_teams[index] == 0:
		return
	_details_team = _button_teams[index]
	_arena.request_roster(_details_team)
	%PVPTeamDetails.show()
	_show_details()


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid():
		refresh()


func _on_visibility_changed() -> void:
	if visible:
		_portrait.show_unit(WowClient.session.get_player_guid())
		show_tab(1)
		refresh()
	else:
		%PVPTeamDetails.hide()
