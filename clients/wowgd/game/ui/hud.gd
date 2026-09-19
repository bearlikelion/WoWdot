class_name Hud
extends Control

signal action_used(slot: int)
signal panel_toggled(panel: MainMenuBar.GamePanel)
signal unit_selected(guid: int)

# WoW lays the interface out on a screen 768 units tall and scales it to the window.
const UI_HEIGHT: float = 768.0
const ERROR_COLOR: Color = Color(1.0, 0.1, 0.1)
const NOTICE_COLOR: Color = Color(1.0, 0.82, 0.0)
# UIParent_ManageFramePositions lifts the casting bar clear of the bottom action bars.
const CASTING_BAR_LIFT: float = 40.0
const SPELL_FAILURES: String = "res://data/classic/spell_failures.json"
const SWING_ERRORS: Dictionary[WowSession.AttackError, String] = {
	WowSession.ATTACK_ERROR_NOT_IN_RANGE: "ERR_BADATTACKPOS",
	WowSession.ATTACK_ERROR_BAD_FACING: "ERR_BADATTACKFACING",
	WowSession.ATTACK_ERROR_NOT_STANDING: "ERR_CANTATTACK_NOTSTANDING",
	WowSession.ATTACK_ERROR_DEAD_TARGET: "ERR_INVALID_ATTACK_TARGET",
	WowSession.ATTACK_ERROR_CANT_ATTACK: "ERR_INVALID_ATTACK_TARGET",
}
# SPELL_FAILED_NO_POWER names the power the player lacks.
const OUT_OF_POWER: Array[String] = [
	"ERR_OUT_OF_MANA", "ERR_OUT_OF_RAGE", "ERR_OUT_OF_FOCUS", "ERR_OUT_OF_ENERGY",
]

var _spell_failures: Dictionary = {}
var _casting_bar_top: float = 0.0

@onready var _ui_parent: Control = %UIParent
@onready var _main_menu_bar: MainMenuBar = %MainMenuBar
@onready var _player_frame: PlayerFrame = %PlayerFrame
@onready var _target_frame: TargetFrame = %TargetFrame
@onready var _errors: WowMessageFrame = %UIErrorsFrame
@onready var _casting_bar: CastingBar = %CastingBarFrame
@onready var _side_bars: SideActionBars = %MultiBarRight
@onready var _minimap: MinimapCluster = %MinimapCluster
@onready var _chat: ChatFrame = %ChatFrame1


func _ready() -> void:
	WowFonts.apply()
	resized.connect(_fit_ui_parent)
	_fit_ui_parent()
	_main_menu_bar.action_used.connect(action_used.emit)
	_main_menu_bar.panel_toggled.connect(panel_toggled.emit)
	_side_bars.action_used.connect(action_used.emit)
	_casting_bar_top = _casting_bar.offset_top
	_main_menu_bar.bottom_bars_toggled.connect(_on_bottom_bars_toggled)
	_on_bottom_bars_toggled(_main_menu_bar.get_node("%MultiBarBottomLeft").visible)
	_player_frame.unit_selected.connect(unit_selected.emit)
	WowClient.session.spell_cast_failed.connect(_on_spell_cast_failed)
	WowClient.session.attack_swing_error.connect(_on_attack_swing_error)
	_spell_failures = JSON.parse_string(FileAccess.get_file_as_string(SPELL_FAILURES))


func show_player(guid: int) -> void:
	_player_frame.show_unit(guid)


func show_target(guid: int) -> void:
	_target_frame.show_unit(guid)


func target() -> int:
	return _target_frame.guid if _target_frame.visible else 0


func add_chat_line(text: String, color: Color = Color.WHITE) -> void:
	_chat.add_message(text, color)


func show_location(map_dir: String, wow_position: Vector3, facing: float) -> void:
	_minimap.show_location(map_dir, wow_position, facing)


func show_area(area_id: int, player_race: int) -> void:
	_minimap.show_area(area_id, player_race)


func show_error(text: String) -> void:
	_errors.add_message(text, ERROR_COLOR)


func show_notice(text: String) -> void:
	_errors.add_message(text, NOTICE_COLOR)


func _on_bottom_bars_toggled(shown: bool) -> void:
	var height: float = _casting_bar.offset_bottom - _casting_bar.offset_top
	_casting_bar.offset_top = _casting_bar_top - (CASTING_BAR_LIFT if shown else 0.0)
	_casting_bar.offset_bottom = _casting_bar.offset_top + height


func _fit_ui_parent() -> void:
	var ui_scale: float = size.y / UI_HEIGHT
	_ui_parent.scale = Vector2(ui_scale, ui_scale)
	_ui_parent.size = size / ui_scale


# Interrupts arrive with reason -1 and are shown by the casting bar instead.
func _on_spell_cast_failed(caster: int, _spell_id: int, reason: int) -> void:
	var session: WowSession = WowClient.session
	if caster != session.get_player_guid() or reason < 0:
		return
	var key: String = _spell_failures.get(str(reason), "")
	if key == "SPELL_FAILED_NO_POWER":
		var power: int = (session.get_field(caster, "UNIT_FIELD_BYTES_0") >> 24) & 0xFF
		key = OUT_OF_POWER[power] if power < OUT_OF_POWER.size() else key
	if not key.is_empty():
		show_error(WowStrings.get_text(key))


func _on_attack_swing_error(error: WowSession.AttackError) -> void:
	show_error(WowStrings.get_text(SWING_ERRORS[error]))


