class_name LoginScreen
extends Control

signal login_requested(realmlist: String, account: String, password: String, remember: bool)
signal quit_requested
signal sound_options_requested
signal video_options_requested

# GetBuildInfo: version type, version, build, build type and build date.
# AccountLogin_OnLoad calls SetModel, so the scene itself names no background.
const GLUE_MODELS: Dictionary[String, String] = {
	"wotlk": "Interface\\Glues\\Models\\UI_MainMenu_Northrend\\UI_MainMenu_Northrend.m2",
}
# DEFAULT_TOOLTIP_COLOR from AccountLogin.lua: border, then background.
const EDIT_BORDER: Color = Color(0.8, 0.8, 0.8)
const EDIT_BACKGROUND: Color = Color(0.09, 0.09, 0.09)

@onready var _realmlist: LineEdit = %AccountLoginRealmlistEdit
@onready var _account: LineEdit = %AccountLoginAccountEdit
@onready var _password: LineEdit = %AccountLoginPasswordEdit
@onready var _remember: WowButton = %AccountLoginSaveAccountName


func _ready() -> void:
	var profile: Dictionary = WowLoader.profile()
	var build_info: Array[String] = [
		"Version", profile["version"], str(profile["build"]),
		ProjectSettings.get_setting("application/config/name", ""), "",
	]
	%AccountLoginVersion.text = (
		WowStrings.get_text("VERSION_TEMPLATE") % build_info
	).strip_edges()
	var background: WowModelFrame = get_node_or_null("%AccountLoginModel") as WowModelFrame
	if background != null and background.model_file.is_empty():
		background.model_file = GLUE_MODELS.get(String(profile["id"]), "")
	for unused: CanvasItem in [%AccountLoginCommunityButton, %AccountLoginManageAccountButton]:
		unused.hide()
	var edits: Array[LineEdit] = [_realmlist, _account, _password]
	for i: int in edits.size():
		var backdrop: WowBackdrop = edits[i].get_node("Backdrop")
		backdrop.border_color = EDIT_BORDER
		backdrop.background_color = EDIT_BACKGROUND
		edits[i].text_submitted.connect(func(_text: String) -> void: log_in())
		edits[i].focus_next = edits[i].get_path_to(edits[(i + 1) % edits.size()])
	%AccountLoginLoginButton.pressed.connect(log_in)
	%AccountLoginExitButton.pressed.connect(quit_requested.emit)
	%AccountLoginSoundOptionsButton.pressed.connect(sound_options_requested.emit)
	%AccountLoginVideoOptionsButton.pressed.connect(video_options_requested.emit)
	_remember.pressed.connect(func() -> void: _remember.checked = not _remember.checked)
	_fit_remember.call_deferred()
	visibility_changed.connect(_on_visibility_changed)


# A FontString with no size of its own converts to a label of no width, and the tick anchored to
# its left edge would land inside the glyphs, so give the label the width its text needs.
func _fit_remember() -> void:
	# 1.12 draws the tick's caption from the button itself and has no label of its own.
	var label: Label = get_node_or_null("%AccountLoginSaveAccountNameText") as Label
	if label == null or label.size.x >= 1.0:
		return
	var width: float = label.get_minimum_size().x
	label.position.x -= width / 2.0
	label.size.x = width
	_remember.global_position.x = label.global_position.x - _remember.size.x


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		quit_requested.emit()


# Under an options panel the controls hide, and Enter or Escape cannot log in or quit behind it.
func set_covered(covered: bool) -> void:
	%AccountLoginUI.visible = not covered
	set_process_unhandled_input(not covered)


func fill(realmlist: String, account: String, password: String = "") -> void:
	_realmlist.text = realmlist
	_account.text = account
	_password.text = password
	_remember.checked = not account.is_empty()


func log_in() -> void:
	login_requested.emit(
		_realmlist.text.strip_edges(), _account.text, _password.text, _remember.checked
	)
	_password.text = ""


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	var edit: LineEdit = _account if _account.text.is_empty() else _password
	edit.grab_focus.call_deferred()
