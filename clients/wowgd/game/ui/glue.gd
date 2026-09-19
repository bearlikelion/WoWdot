class_name Glue
extends Control

enum Screen { LOGIN, CHARACTER_SELECT, CHARACTER_CREATE, LOADING }

const SETTINGS_PATH: String = "user://settings.cfg"
const SETTINGS_SECTION: String = "login"
const DEFAULT_REALMLIST: String = "192.168.1.251"
const AUTH_PORT: int = 3724
const MUSIC: String = "Sound\\Music\\GlueScreenMusic\\wow_main_theme.mp3"
const UI_HEIGHT: float = 768.0
# GlueParent_OnLoad pillarboxes screens wider than 16:9.
const MAX_ASPECT: float = 16.0 / 9.0
# The 1.12.1 ResponseCodes from CHAR_LIST_RETRIEVING on, each named as its GlueStrings key.
const FIRST_CHARACTER_RESPONSE: int = 42
const CHARACTER_RESPONSES: PackedStringArray = [
	"CHAR_LIST_RETRIEVING", "CHAR_LIST_RETRIEVED", "CHAR_LIST_FAILED",
	"CHAR_CREATE_IN_PROGRESS", "CHAR_CREATE_SUCCESS", "CHAR_CREATE_ERROR", "CHAR_CREATE_FAILED",
	"CHAR_CREATE_NAME_IN_USE", "CHAR_CREATE_DISABLED", "CHAR_CREATE_PVP_TEAMS_VIOLATION",
	"CHAR_CREATE_SERVER_LIMIT", "CHAR_CREATE_ACCOUNT_LIMIT", "CHAR_CREATE_SERVER_QUEUE",
	"CHAR_CREATE_ONLY_EXISTING",
	"CHAR_DELETE_IN_PROGRESS", "CHAR_DELETE_SUCCESS", "CHAR_DELETE_FAILED",
	"CHAR_DELETE_FAILED_LOCKED_FOR_TRANSFER",
	"CHAR_LOGIN_IN_PROGRESS", "CHAR_LOGIN_SUCCESS", "CHAR_LOGIN_NO_WORLD",
	"CHAR_LOGIN_DUPLICATE_CHARACTER", "CHAR_LOGIN_NO_INSTANCES", "CHAR_LOGIN_FAILED",
	"CHAR_LOGIN_DISABLED", "CHAR_LOGIN_NO_CHARACTER", "CHAR_LOGIN_LOCKED_FOR_TRANSFER",
	"CHAR_NAME_NO_NAME", "CHAR_NAME_TOO_SHORT", "CHAR_NAME_TOO_LONG",
	"CHAR_NAME_INVALID_CHARACTER", "CHAR_NAME_MIXED_LANGUAGES", "CHAR_NAME_PROFANE",
	"CHAR_NAME_RESERVED", "CHAR_NAME_INVALID_APOSTROPHE", "CHAR_NAME_MULTIPLE_APOSTROPHES",
	"CHAR_NAME_THREE_CONSECUTIVE", "CHAR_NAME_INVALID_SPACE", "CHAR_NAME_CONSECUTIVE_SPACES",
	"CHAR_NAME_FAILURE",
]
const REALM_TYPE_KEYS: Dictionary[RealmList.RealmType, String] = {
	RealmList.RealmType.PVP: "PVP_PARENTHESES",
	RealmList.RealmType.RP: "RP_PARENTHESES",
	RealmList.RealmType.RP_PVP: "RPPVP_PARENTHESES",
}

var _screen: Screen = Screen.LOGIN
var _settings: ConfigFile = ConfigFile.new()
var _realms: Array = []
var _realm_name: String = ""
var _choosing_realm: bool = false
var _characters: Array = []
# Scripted logins enter this character, or the first one when the name is empty.
var _auto_entering: bool = false
var _auto_character: String = ""
# The character just created, selected once the new list arrives.
var _created_name: String = ""

@onready var _parent: Control = %GlueParent
@onready var _login: LoginScreen = %AccountLogin
@onready var _select: CharacterSelect = %CharacterSelect
@onready var _create: CharacterCreate = %CharacterCreate
@onready var _loading: LoadingScreen = %LoadingScreen
@onready var _realm_list: RealmList = %RealmList
@onready var _dialog: GlueDialog = %GlueDialog


func _ready() -> void:
	WowFonts.apply()
	resized.connect(_fit)
	_fit()
	_settings.load(SETTINGS_PATH)
	_realm_name = _settings.get_value(SETTINGS_SECTION, "realm", "")
	_login.fill(_saved_realmlist(), _settings.get_value(SETTINGS_SECTION, "account", ""))
	_login.login_requested.connect(_on_login_requested)
	_login.quit_requested.connect(get_tree().quit)
	_realm_list.realm_chosen.connect(_join_realm)
	_realm_list.cancelled.connect(_on_realm_list_cancelled)
	_select.character_chosen.connect(_on_character_chosen)
	_select.create_requested.connect(_show_screen.bind(Screen.CHARACTER_CREATE))
	_select.delete_requested.connect(_on_delete_requested)
	_select.realm_change_requested.connect(_on_realm_change_requested)
	_select.back_requested.connect(_log_out)
	_create.create_requested.connect(_on_create_requested)
	_create.back_requested.connect(_show_screen.bind(Screen.CHARACTER_SELECT))
	_dialog.status_cancelled.connect(_log_out)
	var session: WowSession = WowClient.session
	session.state_changed.connect(_on_state_changed)
	session.realms_received.connect(_on_realms_received)
	session.characters_received.connect(_on_characters_received)
	session.character_created.connect(_on_character_created)
	session.character_deleted.connect(_on_character_deleted)
	session.character_login_failed.connect(_on_character_login_failed)
	_show_screen(Screen.LOGIN)


func auto_login(realmlist: String, account: String, password: String, character: String) -> void:
	_auto_entering = true
	_auto_character = character
	_login.fill(realmlist if not realmlist.is_empty() else _saved_realmlist(), account, password)
	_login.log_in()


func set_loading_progress(fraction: float) -> void:
	_loading.set_progress(fraction)


func _fit() -> void:
	var ui_scale: float = size.y / UI_HEIGHT
	var width: float = minf(size.x, size.y * MAX_ASPECT)
	_parent.scale = Vector2(ui_scale, ui_scale)
	_parent.size = Vector2(width, size.y) / ui_scale
	_parent.position = Vector2((size.x - width) / 2.0, 0.0)


func _show_screen(screen: Screen) -> void:
	_screen = screen
	_login.visible = screen == Screen.LOGIN
	_select.visible = screen == Screen.CHARACTER_SELECT
	_create.visible = screen == Screen.CHARACTER_CREATE
	_loading.visible = screen == Screen.LOADING
	if screen == Screen.LOADING:
		WowAssets.audio.stop_music()
	else:
		WowAssets.audio.play_music(MUSIC)


func _status(key: String) -> void:
	_dialog.open(GlueDialog.Kind.STATUS, WowStrings.get_text(key))


func _message(text: String) -> void:
	_dialog.open(GlueDialog.Kind.MESSAGE, text)


func _response_text(code: int) -> String:
	var index: int = code - FIRST_CHARACTER_RESPONSE
	if index < 0 or index >= CHARACTER_RESPONSES.size():
		return WowStrings.get_text("CHAR_CREATE_UNKNOWN")
	return WowStrings.get_text(CHARACTER_RESPONSES[index])


func _saved_realmlist() -> String:
	return _settings.get_value(SETTINGS_SECTION, "realmlist", DEFAULT_REALMLIST)


func _log_out() -> void:
	WowClient.session.disconnect()
	_dialog.hide()
	_realm_list.hide()
	_show_screen(Screen.LOGIN)


func _join_realm(index: int) -> void:
	_choosing_realm = false
	_realm_name = _realms[index]["name"]
	_settings.set_value(SETTINGS_SECTION, "realm", _realm_name)
	_settings.save(SETTINGS_PATH)
	WowClient.session.select_realm(index)


func _realm_label() -> String:
	for realm: Dictionary in _realms:
		if realm["name"] == _realm_name:
			var kind: String = REALM_TYPE_KEYS.get(realm["icon"], "")
			return realm["name"] + (" " + WowStrings.get_text(kind) if not kind.is_empty() else "")
	return _realm_name


# A realmlist may name a port after a colon; the stock client always uses 3724.
func _on_login_requested(
	realmlist: String, account: String, password: String, remember: bool,
) -> void:
	if account.is_empty():
		_message(WowStrings.get_text("LOGIN_ENTER_NAME"))
		return
	if password.is_empty():
		_message(WowStrings.get_text("LOGIN_ENTER_PASSWORD"))
		return
	_settings.set_value(SETTINGS_SECTION, "realmlist", realmlist)
	_settings.set_value(SETTINGS_SECTION, "account", account if remember else "")
	_settings.save(SETTINGS_PATH)
	var host: String = realmlist
	var port: int = AUTH_PORT
	if realmlist.count(":") == 1:
		host = realmlist.get_slice(":", 0)
		port = realmlist.get_slice(":", 1).to_int()
	_status("LOGIN_STATE_CONNECTING")
	WowClient.session.login(host, port, account, password)


func _on_state_changed(state: WowSession.State, message: String) -> void:
	match state:
		WowSession.STATE_AUTHENTICATING:
			_status("LOGIN_STATE_AUTHENTICATING")
		WowSession.STATE_CONNECTING_WORLD:
			_status("LOGIN_STATE_CONNECTING")
		WowSession.STATE_CHARACTER_LIST:
			if _screen == Screen.LOADING:
				_show_screen(Screen.CHARACTER_SELECT)
			_status("CHAR_LIST_RETRIEVING")
		WowSession.STATE_FAILED:
			WowClient.session.disconnect()
			_realm_list.hide()
			_show_screen(Screen.LOGIN)
			_message(message if not message.is_empty() else WowStrings.get_text("DISCONNECTED"))


func _on_realms_received(realms: Array) -> void:
	_realms = realms
	var known: int = -1
	for i: int in realms.size():
		if realms[i]["name"] == _realm_name:
			known = i
	if not _choosing_realm and (known >= 0 or realms.size() == 1):
		_join_realm(maxi(known, 0))
		return
	_dialog.hide()
	_realm_list.open(realms, _realm_name)


# Cancelling a realm change goes back to the realm the list was opened from.
func _on_realm_list_cancelled() -> void:
	_choosing_realm = false
	for i: int in _realms.size():
		if _realms[i]["name"] == _realm_name:
			_join_realm(i)
			return
	_log_out()


func _on_realm_change_requested() -> void:
	_choosing_realm = true
	_status("REALM_LIST_IN_PROGRESS")
	WowClient.session.request_realms()


func _on_characters_received(characters: Array) -> void:
	_characters = characters
	_dialog.hide()
	for character: Dictionary in characters:
		if _auto_entering and _auto_character in ["", character["name"]]:
			_auto_entering = false
			_on_character_chosen(character)
			return
	var select_guid: int = 0
	for character: Dictionary in characters:
		if character["name"] == _created_name:
			select_guid = character["guid"]
	_created_name = ""
	_show_screen(Screen.CHARACTER_SELECT)
	_select.show_characters(characters, _realm_label(), select_guid)


func _on_character_chosen(character: Dictionary) -> void:
	_loading.open(character["map"])
	_show_screen(Screen.LOADING)
	WowClient.session.enter_world(character["guid"])


func _on_create_requested(character: Dictionary) -> void:
	_created_name = character["name"]
	_status("CHAR_CREATE_IN_PROGRESS")
	WowClient.session.create_character(character)


func _on_character_created(success: bool, code: int) -> void:
	if success:
		WowClient.session.request_characters()
	else:
		_created_name = ""
		_message(_response_text(code))


func _on_delete_requested(guid: int) -> void:
	_status("CHAR_DELETE_IN_PROGRESS")
	WowClient.session.delete_character(guid)


func _on_character_deleted(success: bool, code: int) -> void:
	if success:
		WowClient.session.request_characters()
	else:
		_message(_response_text(code))


func _on_character_login_failed(code: int) -> void:
	_show_screen(Screen.CHARACTER_SELECT)
	_message(_response_text(code))
