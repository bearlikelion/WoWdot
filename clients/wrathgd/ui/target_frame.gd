@tool
class_name TargetFrame
extends UnitFrame

enum Rank { NORMAL, ELITE, RARE_ELITE, WORLD_BOSS, RARE }

const DYNAMIC_FLAG_TAPPED: int = 0x04
const DYNAMIC_FLAG_TAPPED_BY_PLAYER: int = 0x08
# TargetFrame_CheckLevel shows a skull instead of a level this far above the player.
const SKULL_LEVEL_GAP: int = 10
# TargetFrame.lua builds the target of target and the aura buttons from these templates.
const TARGET_OF_TARGET: PackedScene = preload("res://ui/target_of_target_frame.tscn")
const BUFF_BUTTON: PackedScene = preload("res://ui/target_buff_frame.tscn")
const DEBUFF_BUTTON: PackedScene = preload("res://ui/target_debuff_frame.tscn")
const MAX_TARGET_BUFFS: int = 32
const MAX_TARGET_DEBUFFS: int = 16
const AURA_SIZE: int = 17
const AURA_GAP: int = 3
const AURA_ROW_WIDTH: int = 122
const NORMAL_LEVEL: Color = Color(1.0, 0.82, 0.0)
const TAPPED: Color = Color(0.5, 0.5, 0.5)
const FRIENDLY_PLAYER: Color = Color(0.0, 0.0, 1.0)
const BORDERS: Dictionary[Rank, String] = {
	Rank.NORMAL: "Interface\\TargetingFrame\\UI-TargetingFrame.blp",
	Rank.ELITE: "Interface\\TargetingFrame\\UI-TargetingFrame-Elite.blp",
	Rank.RARE_ELITE: "Interface\\TargetingFrame\\UI-TargetingFrame-Elite.blp",
	Rank.WORLD_BOSS: "Interface\\TargetingFrame\\UI-TargetingFrame-Elite.blp",
	Rank.RARE: "Interface\\TargetingFrame\\UI-TargetingFrame-Rare.blp",
}

var _border_art: Dictionary[Rank, AtlasTexture] = {}
var _target_of_target: TargetOfTargetFrame
var _buffs: Array[Control] = []
var _buff_icons: Array[TextureRect] = []
var _debuffs: Array[Control] = []
var _debuff_icons: Array[TextureRect] = []
var _debuff_borders: Array[TextureRect] = []
var _debuff_counts: Array[Label] = []
var _aura_spells: Dictionary[Control, int] = {}

@onready var _name_background: TextureRect = %TargetFrameNameBackground
@onready var _border: TextureRect = %TargetFrameTextureFrameTexture
@onready var _dead_text: Label = %TargetFrameTextureFrameDeadText
@onready var _skull: TextureRect = %TargetFrameTextureFrameHighLevelTexture


func _ready() -> void:
	if Engine.is_editor_hint():
		super()
		return
	_name_label = %TargetFrameTextureFrameName
	_level_label = %TargetFrameTextureFrameLevelText
	_health_bar = %TargetFrameHealthBar
	_power_bar = %TargetFrameManaBar
	_portrait_rect = %TargetFramePortrait
	# The level text is tinted like SetVertexColor, so it starts from the white font.
	_level_label.theme_type_variation = &"GameFontHighlightSmall"
	# Raid marks and the right-click menu come later.
	for part: CanvasItem in [
		%TargetFrameTextureFrameLeaderIcon, %TargetFrameTextureFrameRaidTargetIcon,
		%TargetFrameTextureFramePVPIcon, %TargetFrameDropDown,
	]:
		part.hide()
	_target_of_target = TARGET_OF_TARGET.instantiate()
	_target_of_target.name = "TargetFrameToT"
	add_child(_target_of_target)
	_target_of_target.unit_selected.connect(unit_selected.emit)
	for i: int in MAX_TARGET_BUFFS:
		var aura_button: Control = _place_aura(BUFF_BUTTON, %TargetFrameBuffs, i)
		_buffs.append(aura_button)
		_buff_icons.append(aura_button.get_node("Icon"))
	for i: int in MAX_TARGET_DEBUFFS:
		var aura_button: Control = _place_aura(DEBUFF_BUTTON, %TargetFrameDebuffs, i)
		_debuffs.append(aura_button)
		_debuff_icons.append(aura_button.get_node("Icon"))
		_debuff_borders.append(aura_button.get_node("Border"))
		_debuff_counts.append(aura_button.get_node("Count"))
	for aura_button: Control in _buffs + _debuffs:
		aura_button.mouse_entered.connect(_on_aura_hovered.bind(aura_button))
		aura_button.mouse_exited.connect(_on_aura_left.bind(aura_button))
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
	_update_target_of_target()
	_update_auras()


func _update_target_of_target() -> void:
	var session: WowSession = WowClient.session
	var of_target: int = session.get_field_guid(guid, "UNIT_FIELD_TARGET")
	_target_of_target.show_unit(of_target if session.has_object(of_target) else 0)


# Rows of small icons under the frame, left to right, as TargetFrame_UpdateAuraPositions lays them.
func _place_aura(template: PackedScene, holder: Control, index: int) -> Control:
	var aura_button: Control = template.instantiate()
	holder.add_child(aura_button)
	@warning_ignore("integer_division")
	var per_row: int = AURA_ROW_WIDTH / (AURA_SIZE + AURA_GAP)
	@warning_ignore("integer_division")
	aura_button.position = Vector2(
		(index % per_row) * (AURA_SIZE + AURA_GAP), (index / per_row) * (AURA_SIZE + AURA_GAP)
	)
	aura_button.size = Vector2(AURA_SIZE, AURA_SIZE)
	aura_button.hide()
	return aura_button


func _update_auras() -> void:
	var helpful: Array[Dictionary] = []
	var harmful: Array[Dictionary] = []
	for aura: Dictionary in UnitAuras.read(WowClient.session, guid):
		(harmful if aura["harmful"] else helpful).append(aura)
	for i: int in _buffs.size():
		_buffs[i].visible = i < helpful.size()
		if _buffs[i].visible:
			_buff_icons[i].texture = WowAssets.spells.icon(helpful[i]["spell"])
			_aura_spells[_buffs[i]] = helpful[i]["spell"]
	for i: int in _debuffs.size():
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
