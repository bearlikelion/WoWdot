class_name VideoOptionsFrame
extends Control

signal close_requested

# VideoOptionsResolutionPanel check buttons and the VideoSettings option each one sets.
const CHECK_OPTIONS: Dictionary[String, StringName] = {
	"Windowed": &"windowed", "Maximized": &"maximized", "VSync": &"vsync",
}
const CHECK_TEXTS: Dictionary[String, String] = {
	"Windowed": "WINDOWED_MODE", "Maximized": "WINDOWED_MAXIMIZED", "VSync": "VERTICAL_SYNC",
}
const MAXIMIZED_CHECK: String = "Maximized"
const WINDOWED_CHECK: String = "Windowed"
const GRAY_FONT_COLOR: Color = Color(0.5, 0.5, 0.5)


func _ready() -> void:
	for key: String in CHECK_OPTIONS:
		_label(key).text = WowStrings.get_text(CHECK_TEXTS[key])
		_check(key).pressed.connect(_on_check_pressed.bind(key))
	%VideoOptionsFrameOkay.pressed.connect(_on_okay_pressed)
	%VideoOptionsFrameApply.pressed.connect(_apply)
	%VideoOptionsFrameCancel.pressed.connect(close_requested.emit)
	%VideoOptionsFrameDefaults.pressed.connect(_show_values.bind(VideoSettings.defaults()))
	visibility_changed.connect(_on_visibility_changed)


# The converter emits the resolution panel twice, so its controls are not unique names.
func _check(key: String) -> WowButton:
	return %VideoOptionsResolutionPanel.get_node("VideoOptionsResolutionPanel" + key)


func _label(key: String) -> Label:
	return _check(key).get_node("VideoOptionsResolutionPanel" + key + "Text")


func _show_values(values: Dictionary) -> void:
	for key: String in CHECK_OPTIONS:
		_check(key).checked = values[CHECK_OPTIONS[key]]
	_update_dependency()


# OptionsFrame_DisableCheckBox: Maximized only means something for a window.
func _update_dependency() -> void:
	var windowed: bool = _check(WINDOWED_CHECK).checked
	_check(MAXIMIZED_CHECK).disabled = not windowed
	_label(MAXIMIZED_CHECK).self_modulate = Color.WHITE if windowed else GRAY_FONT_COLOR


func _apply() -> void:
	var video: VideoSettings = WowAssets.video
	for key: String in CHECK_OPTIONS:
		video.set(CHECK_OPTIONS[key], _check(key).checked)
	video.apply()
	video.save()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	var video: VideoSettings = WowAssets.video
	var values: Dictionary = {}
	for option: StringName in VideoSettings.OPTIONS:
		values[option] = video.get(option)
	_show_values(values)


func _on_check_pressed(key: String) -> void:
	_check(key).checked = not _check(key).checked
	_update_dependency()


func _on_okay_pressed() -> void:
	_apply()
	close_requested.emit()
