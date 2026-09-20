class_name GameMenu
extends Control

signal close_requested
signal sound_options_requested
signal video_options_requested
signal interface_options_requested
signal key_bindings_requested


func _ready() -> void:
	# The macro window is not ported yet.
	(%GameMenuButtonMacros as BaseButton).disabled = true
	%GameMenuButtonUIOptions.pressed.connect(interface_options_requested.emit)
	%GameMenuButtonKeybindings.pressed.connect(key_bindings_requested.emit)
	%GameMenuButtonOptions.pressed.connect(video_options_requested.emit)
	%GameMenuButtonSoundOptions.pressed.connect(sound_options_requested.emit)
	%GameMenuButtonLogout.pressed.connect(_on_logout_pressed)
	%GameMenuButtonQuit.pressed.connect(get_tree().quit)
	%GameMenuButtonContinue.pressed.connect(close_requested.emit)


func _on_logout_pressed() -> void:
	close_requested.emit()
	WowClient.session.logout()
