class_name GameMenu
extends Control

signal close_requested
signal sound_options_requested
signal video_options_requested


func _ready() -> void:
	# The interface options, key binding and macro windows are not ported yet.
	for unported: BaseButton in [
		%GameMenuButtonUIOptions, %GameMenuButtonKeybindings, %GameMenuButtonMacros,
	]:
		unported.disabled = true
	%GameMenuButtonOptions.pressed.connect(video_options_requested.emit)
	%GameMenuButtonSoundOptions.pressed.connect(sound_options_requested.emit)
	%GameMenuButtonLogout.pressed.connect(_on_logout_pressed)
	%GameMenuButtonQuit.pressed.connect(get_tree().quit)
	%GameMenuButtonContinue.pressed.connect(close_requested.emit)


func _on_logout_pressed() -> void:
	close_requested.emit()
	WowClient.session.logout()
