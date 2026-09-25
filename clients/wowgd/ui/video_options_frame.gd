class_name VideoOptionsFrame
extends Control

signal close_requested

# Check button numbers in wowgd.xml and the VideoSettings option each one sets.
const CHECK_OPTIONS: Dictionary[int, StringName] = {
	1: &"windowed", 2: &"maximized", 3: &"vsync", 4: &"shadows", 5: &"volumetric_fog",
}
# GlobalStrings keys; stock 1.12 has none of the other options, so their labels are our own.
const CHECK_TEXTS: Dictionary[int, String] = {
	1: "WINDOWED_MODE", 2: "WINDOWED_MAXIMIZED", 3: "VERTICAL_SYNC",
}
const OWN_TEXTS: Dictionary[int, String] = {4: "Shadows", 5: "Volumetric Fog"}
const MAXIMIZED_CHECK: int = 2
const WINDOWED_CHECK: int = 1
const SHADOWS_CHECK: int = 4
const VOLUMETRIC_CHECK: int = 5
const GRAY_FONT_COLOR: Color = Color(0.5, 0.5, 0.5)
const DROP_DOWN_LIST: PackedScene = preload("res://ui/drop_down_list.tscn")
# The screen's own size joins these, and any larger than the screen are left out.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(800, 600), Vector2i(1024, 768), Vector2i(1280, 720), Vector2i(1280, 960),
	Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1680, 1050), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160),
]
const MENU_OFFSET: Vector2 = Vector2(15.0, 32.0)

var _resolution: Vector2i = Vector2i.ZERO
var _resolutions: Array[Vector2i] = []
var _menu: DropDownList
var _language: String = ""
var _language_menu: DropDownList


func _ready() -> void:
	for number: int in CHECK_OPTIONS:
		var text: String = OWN_TEXTS[number] if OWN_TEXTS.has(number) \
		else WowStrings.get_text(CHECK_TEXTS[number])
		_label(number).text = text
		_check(number).pressed.connect(_on_check_pressed.bind(number))
	%VideoOptionsFrameOkay.pressed.connect(_on_okay_pressed)
	%VideoOptionsFrameCancel.pressed.connect(close_requested.emit)
	%VideoOptionsFrameDefaults.pressed.connect(_show_values.bind(VideoSettings.defaults()))
	visibility_changed.connect(_on_visibility_changed)
	%VideoOptionsFrameResolutionDropDownButton.pressed.connect(_open_resolution_menu)
	_menu = DROP_DOWN_LIST.instantiate()
	add_child(_menu)
	_menu.entry_selected.connect(_on_resolution_selected)
	%VideoOptionsFrameLanguageDropDownLabel.text = WowStrings.get_text("LANGUAGE", "Language")
	%VideoOptionsFrameLanguageDropDownButton.pressed.connect(_open_language_menu)
	_language_menu = DROP_DOWN_LIST.instantiate()
	add_child(_language_menu)
	_language_menu.entry_selected.connect(_on_language_selected)


func _check(number: int) -> WowButton:
	return get_node("%%VideoOptionsFrameCheckButton%d" % number)


func _label(number: int) -> Label:
	return _check(number).get_node("VideoOptionsFrameCheckButton%dText" % number)


func _show_values(values: Dictionary) -> void:
	for number: int in CHECK_OPTIONS:
		_check(number).checked = values[CHECK_OPTIONS[number]]
	_resolution = values[&"resolution"]
	_show_resolution()
	_update_dependency()


# Unset, the dropdown shows the size the window already is.
func _show_resolution() -> void:
	var size: Vector2i = _resolution if _resolution != Vector2i.ZERO \
	else DisplayServer.window_get_size()
	%VideoOptionsFrameResolutionDropDownText.text = "%dx%d" % [size.x, size.y]


# OptionsFrame_DisableCheckBox: Maximized needs a window, and fog only shows shafts in shadow.
func _update_dependency() -> void:
	_enable(MAXIMIZED_CHECK, _check(WINDOWED_CHECK).checked)
	_enable(VOLUMETRIC_CHECK, _check(SHADOWS_CHECK).checked)


func _enable(number: int, on: bool) -> void:
	_check(number).disabled = not on
	_label(number).self_modulate = Color.WHITE if on else GRAY_FONT_COLOR


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	var video: VideoSettings = WowAssets.video
	var values: Dictionary = {}
	for option: StringName in VideoSettings.OPTIONS:
		values[option] = video.get(option)
	values[&"resolution"] = video.resolution
	_show_values(values)
	_language = video.locale
	_show_language()


func _on_check_pressed(number: int) -> void:
	_check(number).checked = not _check(number).checked
	_update_dependency()


func _open_resolution_menu() -> void:
	var screen: Vector2i = DisplayServer.screen_get_size()
	_resolutions.clear()
	for size: Vector2i in RESOLUTIONS:
		if size.x <= screen.x and size.y <= screen.y and size != screen:
			_resolutions.append(size)
	_resolutions.append(screen)
	var shown: String = %VideoOptionsFrameResolutionDropDownText.text
	var entries: Array[Dictionary] = []
	for i: int in _resolutions.size():
		var text: String = "%dx%d" % [_resolutions[i].x, _resolutions[i].y]
		entries.append({"text": text, "id": i, "checked": text == shown})
	_menu.open(entries, %VideoOptionsFrameResolutionDropDown.position + MENU_OFFSET)


func _on_resolution_selected(id: int) -> void:
	_resolution = _resolutions[id]
	_show_resolution()


func _show_language() -> void:
	%VideoOptionsFrameLanguageDropDownText.text = Translations.LOCALES[_language]


func _open_language_menu() -> void:
	var available: PackedStringArray = VideoSettings.available_locales()
	var entries: Array[Dictionary] = []
	for i: int in Translations.LOCALES.size():
		var code: String = Translations.LOCALES.keys()[i]
		entries.append({
			"text": Translations.LOCALES[code],
			"id": i,
			"checked": code == _language,
			"disabled": not code in available,
		})
	_language_menu.open(entries, %VideoOptionsFrameLanguageDropDown.position + MENU_OFFSET)


func _on_language_selected(id: int) -> void:
	_language = Translations.LOCALES.keys()[id]
	_show_language()


func _on_okay_pressed() -> void:
	var video: VideoSettings = WowAssets.video
	video.locale = _language
	for number: int in CHECK_OPTIONS:
		video.set(CHECK_OPTIONS[number], _check(number).checked)
	video.resolution = _resolution
	video.apply()
	video.save()
	close_requested.emit()
