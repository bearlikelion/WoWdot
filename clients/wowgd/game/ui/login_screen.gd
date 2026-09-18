class_name LoginScreen
extends Control

signal realm_joined

const AUTH_PORT: int = 3724
const STATUS_TEXT: Dictionary[WowSession.State, String] = {
	WowSession.STATE_AUTHENTICATING: "Logging in...",
	WowSession.STATE_REALM_LIST: "Joining realm...",
	WowSession.STATE_CONNECTING_WORLD: "Connecting to the realm...",
}

@onready var _host: LineEdit = %Host
@onready var _account: LineEdit = %Account
@onready var _password: LineEdit = %Password
@onready var _login_button: Button = %LoginButton
@onready var _status: Label = %Status


func _ready() -> void:
	_login_button.pressed.connect(log_in)
	_password.text_submitted.connect(_on_password_submitted)
	WowClient.session.state_changed.connect(_on_state_changed)
	WowClient.session.realms_received.connect(_on_realms_received)


func log_in() -> void:
	_login_button.disabled = true
	WowClient.session.login(_host.text, AUTH_PORT, _account.text, _password.text)


func fill_credentials(account: String, password: String) -> void:
	_account.text = account
	_password.text = password


func _on_password_submitted(_text: String) -> void:
	log_in()


func _on_state_changed(state: WowSession.State, message: String) -> void:
	if state == WowSession.STATE_FAILED:
		_status.text = message
		_login_button.disabled = false
	elif state == WowSession.STATE_CHARACTER_LIST:
		_status.text = ""
		realm_joined.emit()
	else:
		_status.text = STATUS_TEXT.get(state, "")


# ponytail: joins the first realm; add a realm picker once a second realm exists.
func _on_realms_received(_realms: Array) -> void:
	WowClient.session.select_realm(0)
