class_name HonorFrame
extends Control

# The first four rank bytes are the dishonorable ranks, so Private, rank 1, is byte 5.
const RANK_OFFSET: int = 4
const RANK_GAP: float = 5.0
const RANK_BADGE: String = "Interface\\PvPRankBadges\\PvPRank%02d.blp"
const ALLIANCE_BAR: Color = Color(0.05, 0.15, 0.36)
const HORDE_BAR: Color = Color(0.63, 0.09, 0.09)
# Label to the player field it shows.
const COUNTS: Dictionary[String, String] = {
	"HonorFrameYesterdayHKValue": "PLAYER_FIELD_YESTERDAY_KILLS",
	"HonorFrameYesterdayContributionValue": "PLAYER_FIELD_YESTERDAY_CONTRIBUTION",
	"HonorFrameThisWeekHKValue": "PLAYER_FIELD_THIS_WEEK_KILLS",
	"HonorFrameThisWeekContributionValue": "PLAYER_FIELD_THIS_WEEK_CONTRIBUTION",
	"HonorFrameLastWeekHKValue": "PLAYER_FIELD_LAST_WEEK_KILLS",
	"HonorFrameLastWeekContributionValue": "PLAYER_FIELD_LAST_WEEK_CONTRIBUTION",
	"HonorFrameLastWeekStandingValue": "PLAYER_FIELD_LAST_WEEK_RANK",
	"HonorFrameLifeTimeHKValue": "PLAYER_FIELD_LIFETIME_HONORBALE_KILLS",
	"HonorFrameLifeTimeDKValue": "PLAYER_FIELD_LIFETIME_DISHONORBALE_KILLS",
}


func _ready() -> void:
	visibility_changed.connect(refresh)
	WowClient.session.object_updated.connect(_on_object_updated)


func refresh() -> void:
	if not is_visible_in_tree():
		return
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	for label: String in COUNTS:
		(get_node("%" + label) as Label).text = str(session.get_field(guid, COUNTS[label]))
	# Today's honorable and dishonorable kills share one field, sixteen bits each.
	var today: int = session.get_field(guid, "PLAYER_FIELD_SESSION_KILLS")
	%HonorFrameCurrentHKValue.text = str(today & 0xFFFF)
	%HonorFrameCurrentDKValue.text = str((today >> 16) & 0xFFFF)
	var bytes_0: int = session.get_field(guid, "UNIT_FIELD_BYTES_0")
	var race: int = bytes_0 & 0xFF
	%HonorLevelText.text = WowStrings.get_text("PLAYER_LEVEL") % [
		session.get_field(guid, "UNIT_FIELD_LEVEL"), CharacterOptions.race_name(race),
		CharacterOptions.class_label((bytes_0 >> 8) & 0xFF),
	]
	%HonorGuildText.hide()
	var alliance: bool = CharacterOptions.faction(race) == CharacterOptions.Faction.ALLIANCE
	var rank: int = (session.get_field(guid, "PLAYER_BYTES_3") >> 24) & 0xFF
	var highest: int = (session.get_field(guid, "PLAYER_FIELD_BYTES") >> 24) & 0xFF
	%HonorFrameLifeTimeRankValue.text = rank_name(highest, alliance)
	%HonorFrameCurrentPVPTitle.text = rank_name(rank, alliance)
	var number: int = maxi(rank - RANK_OFFSET, 0)
	%HonorFrameCurrentPVPRank.text = "(%s %d)" % [WowStrings.get_text("RANK"), number]
	center_rank.call_deferred(%HonorFrameCurrentPVPTitle, %HonorFrameCurrentPVPRank, size.x)
	var badge: TextureRect = %HonorFramePvPIcon
	badge.visible = number > 0
	if number > 0:
		var texture: WowTexture = WowTexture.new()
		texture.file = RANK_BADGE % number
		badge.texture = texture
	var bar: TextureProgressBar = %HonorFrameProgressBar
	bar.tint_progress = ALLIANCE_BAR if alliance else HORDE_BAR
	bar.max_value = 255.0
	bar.value = session.get_field(guid, "PLAYER_FIELD_BYTES2") & 0xFF


# HonorFrame_Update recentres the pair: the title, then its rank in brackets right after it.
static func center_rank(title: Label, rank: Label, width: float) -> void:
	var title_width: float = title.get_minimum_size().x
	var rank_width: float = rank.get_minimum_size().x
	title.size.x = title_width
	rank.size.x = rank_width
	title.position.x = (width - title_width - rank_width - RANK_GAP) / 2.0
	rank.position = Vector2(title.position.x + title_width + RANK_GAP, title.position.y)


# The rank strings end in 1 for the Alliance's titles and 0 for the Horde's.
static func rank_name(rank: int, alliance: bool) -> String:
	if rank == 0:
		return WowStrings.get_text("NONE")
	return WowStrings.get_text("PVP_RANK_%d_%d" % [rank, 1 if alliance else 0])


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid():
		refresh()
