class_name OptionsSelectFrame
extends Control

signal video_options_requested
signal sound_options_requested
signal close_requested


func _ready() -> void:
	%OptionsSelectFrameBackgroundContainerVideoOptionsButton.pressed.connect(
		video_options_requested.emit
	)
	%OptionsSelectFrameBackgroundContainerAudioOptionsButton.pressed.connect(
		sound_options_requested.emit
	)
	%OptionsSelectFrameBackgroundOkayButton.pressed.connect(close_requested.emit)
	# ponytail: no reset, as each panel keeps its own settings; add one once they share a store.
	%OptionsSelectResetSettingsButton.disabled = true
