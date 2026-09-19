class_name KeyBindings
extends RefCounted

# Stock 1.12 keys for bindings project.godot lacks; one each, as PackedStringArray values crash here.
const DEFAULTS: Dictionary[String, String] = {
	"target_nearest_friend": "Ctrl+Tab",
	"target_previous_friend": "Ctrl+Shift+Tab",
	"target_self": "F1",
	"target_last_hostile": "G",
	"assist_target": "F",
	"attack_target": "T",
}


static func apply() -> void:
	for action: String in DEFAULTS:
		if InputMap.has_action(action):
			continue
		var parts: PackedStringArray = DEFAULTS[action].split("+")
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = OS.find_keycode_from_string(parts[parts.size() - 1])
		event.shift_pressed = parts.has("Shift")
		event.ctrl_pressed = parts.has("Ctrl")
		event.alt_pressed = parts.has("Alt")
		InputMap.add_action(action)
		InputMap.action_add_event(action, event)
