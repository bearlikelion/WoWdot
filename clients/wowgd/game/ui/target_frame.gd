@tool
class_name TargetFrame
extends UnitFrame

enum Rank { NORMAL, ELITE, RARE_ELITE, WORLD_BOSS, RARE }

const DYNAMIC_FLAG_TAPPED: int = 0x04
const DYNAMIC_FLAG_TAPPED_BY_PLAYER: int = 0x08
# TargetFrame_CheckLevel shows a skull instead of a level this far above the player.
const SKULL_LEVEL_GAP: int = 10
const NORMAL_LEVEL: Color = Color(1.0, 0.82, 0.0)
const TAPPED: Color = Color(0.5, 0.5, 0.5)
const FRIENDLY_PLAYER: Color = Color(0.0, 0.0, 1.0)
const TARGET_BUFFS: int = 5
const TARGET_DEBUFFS: int = 16
const BORDERS: Dictionary[Rank, String] = {
	Rank.NORMAL: "Interface\\TargetingFrame\\UI-TargetingFrame.blp",
	Rank.ELITE: "Interface\\TargetingFrame\\UI-TargetingFrame-Elite.blp",
	Rank.RARE_ELITE: "Interface\\TargetingFrame\\UI-TargetingFrame-Elite.blp",
	Rank.WORLD_BOSS: "Interface\\TargetingFrame\\UI-TargetingFrame-Elite.blp",
	Rank.RARE: "Interface\\TargetingFrame\\UI-TargetingFrame-Rare.blp",
}

var _border_art: Dictionary[Rank, AtlasTexture] = {}
var _buffs: Array[Control] = []
var _buff_icons: Array[TextureRect] = []
var _debuffs: Array[Control] = []
var _debuff_icons: Array[TextureRect] = []
var _debuff_borders: Array[TextureRect] = []
var _debuff_counts: Array[Label] = []
var _aura_spells: Dictionary[Control, int] = {}

@onready var _name_background: TextureRect = %TargetFrameNameBackground
@onready var _border: TextureRect = %TargetFrameTexture
@onready var _dead_text: Label = %TargetDeadText
@onready var _skull: TextureRect = %TargetHighLevelTexture


func _ready() -> void:
	if Engine.is_editor_hint():
		super()
		return
	_name_label = %TargetName
	_level_label = %TargetLevelText
	_health_bar = %TargetFrameHealthBar
	_power_bar = %TargetFrameManaBar
	_portrait_rect = %TargetPortrait
	# The level text is tinted like SetVertexColor, so it starts from the white font.
	_level_label.theme_type_variation = &"GameFontHighlightSmall"
	# Target of target, raid marks and the right-click menu come later.
	for part: CanvasItem in [
		%TargetofTargetFrame, %TargetLeaderIcon, %TargetRaidTargetIcon, %TargetPVPIcon,
		%TargetFrameDropDown,
	]:
		part.hide()
	for i: int in range(1, TARGET_BUFFS + 1):
		_buffs.append(get_node("%%TargetFrameBuff%d" % i))
		_buff_icons.append(get_node("%%TargetFrameBuff%dIcon" % i))
	for i: int in range(1, TARGET_DEBUFFS + 1):
		_debuffs.append(get_node("%%TargetFrameDebuff%d" % i))
	for aura_button: Control in _buffs + _debuffs:
		aura_button.mouse_entered.connect(_on_aura_hovered.bind(aura_button))
		aura_button.mouse_exited.connect(_on_aura_left.bind(aura_button))
	for i: int in range(1, TARGET_DEBUFFS + 1):
		_debuff_icons.append(get_node("%%TargetFrameDebuff%dIcon" % i))
		_debuff_borders.append(get_node("%%TargetFrameDebuff%dBorder" % i))
		_debuff_counts.append(get_node("%%TargetFrameDebuff%dCount" % i))
	var normal: AtlasTexture = _border.texture as AtlasTexture
	for rank: Rank in BORDERS:
		var art: AtlasTexture = normal.duplicate()
		var file: WowTexture = WowTexture.new()
		file.file = BORDERS[rank]
		art.atlas = file
		_border_art[rank] = art
	super()


func _update_unit() -> void:
	var session: WowSession = WowClient.session
	var player: int = session.get_player_guid()
	var reaction: UnitReaction.Reaction = UnitReaction.between(session, player, guid)
	var hostile: bool = reaction == UnitReaction.Reaction.HOSTILE
	var is_player: bool = session.get_object_type(guid) == Entities.ObjectType.PLAYER
	var dynamic: int = session.get_field(guid, "UNIT_DYNAMIC_FLAGS")
	var tapped: bool = dynamic & DYNAMIC_FLAG_TAPPED != 0 \
	and dynamic & DYNAMIC_FLAG_TAPPED_BY_PLAYER == 0
	if tapped:
		_name_background.self_modulate = TAPPED
	elif is_player and not hostile:
		_name_background.self_modulate = FRIENDLY_PLAYER
	else:
		_name_background.self_modulate = UnitReaction.COLORS[reaction]
	_portrait_rect.self_modulate = TAPPED if tapped else Color.WHITE

	var level: int = session.get_field(guid, "UNIT_FIELD_LEVEL")
	var player_level: int = session.get_field(player, "UNIT_FIELD_LEVEL")
	var skull: bool = hostile and level >= player_level + SKULL_LEVEL_GAP
	_skull.visible = skull
	_level_label.visible = not skull
	var level_tint: Color = NORMAL_LEVEL
	if hostile:
		level_tint = UnitReaction.level_color(level, player_level)
	_level_label.self_modulate = level_tint

	var rank: Rank = session.get_creature_info(guid).get("rank", Rank.NORMAL) as Rank
	_border.texture = _border_art.get(rank, _border_art[Rank.NORMAL])
	_dead_text.visible = session.get_field(guid, "UNIT_FIELD_HEALTH") == 0
	_update_auras()


func _update_auras() -> void:
	var helpful: Array[Dictionary] = []
	var harmful: Array[Dictionary] = []
	for aura: Dictionary in UnitAuras.read(WowClient.session, guid):
		(harmful if aura["harmful"] else helpful).append(aura)
	for i: int in TARGET_BUFFS:
		_buffs[i].visible = i < helpful.size()
		if _buffs[i].visible:
			_buff_icons[i].texture = WowAssets.spells.icon(helpful[i]["spell"])
			_aura_spells[_buffs[i]] = helpful[i]["spell"]
	for i: int in TARGET_DEBUFFS:
		_debuffs[i].visible = i < harmful.size()
		if not _debuffs[i].visible:
			continue
		var aura: Dictionary = harmful[i]
		_aura_spells[_debuffs[i]] = aura["spell"]
		_debuff_icons[i].texture = WowAssets.spells.icon(aura["spell"])
		_debuff_borders[i].self_modulate = UnitAuras.border_color(aura["spell"])
		_debuff_counts[i].visible = aura["stacks"] > 1
		_debuff_counts[i].text = str(aura["stacks"])


# Target auras anchor their tooltip below and right of the icon, as TargetFrame.xml does.
func _on_aura_hovered(button: Control) -> void:
	if _aura_spells.has(button) and GameTooltip.current:
		var anchor: GameTooltip.TooltipAnchor = GameTooltip.TooltipAnchor.BOTTOM_RIGHT
		GameTooltip.current.set_aura(button, _aura_spells[button], anchor)


func _on_aura_left(button: Control) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(button)
