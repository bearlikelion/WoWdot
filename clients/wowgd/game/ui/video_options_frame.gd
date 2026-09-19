class_name VideoOptionsFrame
extends Control

signal close_requested

# Check button numbers in wowgd.xml and the VideoSettings option each one sets.
const CHECK_OPTIONS: Dictionary[int, StringName] = {
	1: &"windowed", 2: &"maximized", 3: &"vsync", 4: &"shadows",
}
# GlobalStrings keys; stock 1.12 has no shadow option, so that label is our own.
const CHECK_TEXTS: Dictionary[int, String] = {
	1: "WINDOWED_MODE", 2: "WINDOWED_MAXIMIZED", 3: "VERTICAL_SYNC",
}
const SHADOWS_TEXT: String = "Shadows"
const SHADOWS_CHECK: int = 4
const MAXIMIZED_CHECK: int = 2
const WINDOWED_CHECK: int = 1
const GRAY_FONT_COLOR: Color = Color(0.5, 0.5, 0.5)


func _ready() -> void:
	for number: int in CHECK_OPTIONS:
		var text: String = SHADOWS_TEXT if number == SHADOWS_CHECK \
		else WowStrings.get_text(CHECK_TEXTS[number])
		_label(number).text = text
		_check(number).pressed.connect(_on_check_pressed.bind(number))
	%VideoOptionsFrameOkay.pressed.connect(_on_okay_pressed)
	%VideoOptionsFrameCancel.pressed.connect(close_requested.emit)
	%VideoOptionsFrameDefaults.pressed.connect(_show_values.bind(VideoSettings.defaults()))
	visibility_changed.connect(_on_visibility_changed)


func _check(number: int) -> WowButton:
	return get_node("%%VideoOptionsFrameCheckButton%d" % number)


func _label(number: int) -> Label:
	return _check(number).get_node("VideoOptionsFrameCheckButton%dText" % number)


func _show_values(values: Dictionary) -> void:
	for number: int in CHECK_OPTIONS:
		_check(number).checked = values[CHECK_OPTIONS[number]]
	_update_dependency()


# OptionsFrame_DisableCheckBox: Maximized only means something for a window.
func _update_dependency() -> void:
	var windowed: bool = _check(WINDOWED_CHECK).checked
	_check(MAXIMIZED_CHECK).disabled = not windowed
	_label(MAXIMIZED_CHECK).self_modulate = Color.WHITE if windowed else GRAY_FONT_COLOR


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	var video: VideoSettings = WowAssets.video
	var values: Dictionary = {}
	for option: StringName in VideoSettings.OPTIONS:
		values[option] = video.get(option)
	_show_values(values)


func _on_check_pressed(number: int) -> void:
	_check(number).checked = not _check(number).checked
	_update_dependency()


func _on_okay_pressed() -> void:
	var video: VideoSettings = WowAssets.video
	for number: int in CHECK_OPTIONS:
		video.set(CHECK_OPTIONS[number], _check(number).checked)
	video.apply()
	video.save()
	close_requested.emit()
