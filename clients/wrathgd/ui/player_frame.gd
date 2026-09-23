@tool
class_name PlayerFrame
extends UnitFrame

const PLAYER_FLAG_RESTING: int = 0x20
const UNIT_FLAG_IN_COMBAT: int = 0x80000
# PlayerFrame_UpdateStatus tints the status texture yellow while resting and red in combat.
const RESTING_TINT: Color = Color(1.0, 0.88, 0.25)
const COMBAT_TINT: Color = Color(1.0, 0.0, 0.0)
const DRUID: int = 11

var _feedback: CombatFeedback

@onready var _status: TextureRect = %PlayerStatusTexture
@onready var _rest_icon: TextureRect = %PlayerRestIcon
@onready var _rest_glow: TextureRect = %PlayerRestGlow
@onready var _attack_icon: TextureRect = %PlayerAttackIcon
@onready var _attack_glow: TextureRect = %PlayerAttackGlow
@onready var _attack_background: TextureRect = %PlayerAttackBackground


func _ready() -> void:
	if Engine.is_editor_hint():
		super()
		return
	_name_label = %PlayerName
	_level_label = %PlayerLevelText
	_health_bar = %PlayerFrameHealthBar
	_power_bar = %PlayerFrameManaBar
	_health_text = %PlayerFrameHealthBarText
	_power_text = %PlayerFrameManaBarText
	_portrait_rect = %PlayerPortrait
	# Pets, groups and the play-time warning have their own phases; the frame starts without them.
	for part: CanvasItem in [
		%PetFrame, %PlayerFrameGroupIndicator, %PlayerLeaderIcon, %PlayerMasterIcon,
		%PlayerFrameDropDown, %PlayerPlayTime, %PlayerPVPIcon,
	]:
		part.hide()
	super()
	_feedback = CombatFeedback.new(%PlayerHitIndicator)
	WowClient.combat.logged.connect(_on_combat_logged)


func _update_unit() -> void:
	var session: WowSession = WowClient.session
	var in_combat: bool = session.get_field(guid, "UNIT_FIELD_FLAGS") & UNIT_FLAG_IN_COMBAT != 0
	var resting: bool = not in_combat \
	and session.get_field(guid, "PLAYER_FLAGS") & PLAYER_FLAG_RESTING != 0
	_attack_icon.visible = in_combat
	_attack_glow.visible = in_combat
	_attack_background.visible = in_combat
	_rest_icon.visible = resting
	_rest_glow.visible = resting
	_status.visible = in_combat or resting
	_status.self_modulate = COMBAT_TINT if in_combat else RESTING_TINT
	_update_alternate_mana(session)


# AlternatePowerBar: a druid in a form that runs on rage or energy still sees their mana.
func _update_alternate_mana(session: WowSession) -> void:
	var bytes_0: int = session.get_field(guid, "UNIT_FIELD_BYTES_0")
	var shifted: bool = (bytes_0 >> 8) & 0xFF == DRUID \
			and (bytes_0 >> 24) & 0xFF != PowerType.MANA
	var bar: TextureProgressBar = %PlayerFrameAlternateManaBar
	bar.visible = shifted
	if shifted:
		var mana: int = session.get_field(guid, "UNIT_FIELD_POWER1")
		var max_mana: int = session.get_field(guid, "UNIT_FIELD_MAXPOWER1")
		bar.max_value = maxi(max_mana, 1)
		bar.value = mana
		(%PlayerFrameAlternateManaBarText as Label).text = "%d / %d" % [mana, max_mana]


# PlayerFrame_OnEvent passes UNIT_COMBAT for the player to CombatFeedback.
func _on_combat_logged(event: CombatEvents.CombatEvent) -> void:
	if guid != 0 and event.target == guid:
		_feedback.show_event(event)
