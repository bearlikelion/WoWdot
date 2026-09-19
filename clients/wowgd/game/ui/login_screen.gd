class_name LoginScreen
extends Control

signal login_requested(realmlist: String, account: String, password: String, remember: bool)
signal quit_requested

# GetBuildInfo: version type, version, build, build type and build date.
const BUILD_INFO: Array[String] = ["Version", "1.12.1", "5875", "WoWGD", ""]
# DEFAULT_TOOLTIP_COLOR from AccountLogin.lua: border, then background.
const EDIT_BORDER: Color = Color(0.8, 0.8, 0.8)
const EDIT_BACKGROUND: Color = Color(0.09, 0.09, 0.09)

@onready var _realmlist: LineEdit = %AccountLoginRealmlistEdit
@onready var _account: LineEdit = %AccountLoginAccountEdit
@onready var _password: LineEdit = %AccountLoginPasswordEdit
@onready var _remember: WowButton = %AccountLoginSaveAccountName


func _ready() -> void:
	%AccountLoginVersion.text = (WowStrings.get_text("VERSION_TEMPLATE") % BUILD_INFO).strip_edges()
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
	_remember.pressed.connect(func() -> void: _remember.checked = not _remember.checked)
	visibility_changed.connect(_on_visibility_changed)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		quit_requested.emit()


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
