class_name InterfaceSettings
extends RefCounted

signal changed

const SETTINGS_PATH: String = "user://interface.cfg"
const SECTION: String = "interface"
# The stock options this client answers, by the name UIOptionsFrame.lua gives each one.
const OPTIONS: Dictionary[StringName, bool] = {
	&"invert_mouse": false,
	&"status_bar_text": false,
	&"show_buff_durations": true,
	&"auto_quest_watch": true,
	&"chat_bubbles": true,
	&"party_chat_bubbles": false,
	&"show_player_names": true,
	&"show_npc_names": true,
	&"show_own_name": false,
	&"show_helm": true,
	&"show_cloak": true,
	&"multi_bar_1": true,
	&"multi_bar_2": true,
	&"multi_bar_3": true,
	&"multi_bar_4": true,
	# This client's own option, which the stock window has no check button for.
	&"show_map_pois": true,
}

var _values: Dictionary[StringName, bool] = {}


func _init() -> void:
	var saved: ConfigFile = ConfigFile.new()
	var has_saved: bool = saved.load(SETTINGS_PATH) == OK
	for option: StringName in OPTIONS:
		_values[option] = saved.get_value(SECTION, option, OPTIONS[option]) if has_saved \
		else OPTIONS[option]


func is_on(option: StringName) -> bool:
	return _values.get(option, OPTIONS.get(option, false))


func set_on(option: StringName, value: bool) -> void:
	if _values.get(option) == value:
		return
	_values[option] = value
	changed.emit()


func restore_defaults() -> void:
	_values = OPTIONS.duplicate()
	changed.emit()


func save() -> void:
	var saved: ConfigFile = ConfigFile.new()
	for option: StringName in OPTIONS:
		saved.set_value(SECTION, option, is_on(option))
	saved.save(SETTINGS_PATH)
