class_name KeyBindings
extends RefCounted

const SETTINGS_PATH: String = "user://bindings.cfg"
const SECTION: String = "bindings"
const BINDINGS_XML: String = "Interface\\FrameXML\\Bindings.xml"
# Stock keys for bindings project.godot lacks; one each, as PackedStringArray values crash here.
const DEFAULTS: Dictionary[String, String] = {
	"target_nearest_friend": "Ctrl+Tab",
	"target_previous_friend": "Ctrl+Shift+Tab",
	"target_self": "F1",
	"target_last_hostile": "G",
	"assist_target": "F",
	"attack_target": "T",
	"toggle_reputation": "U",
	"toggle_sheath": "Z",
	"toggle_backpack": "F12",
	"toggle_bag_1": "F11",
	"toggle_bag_2": "F10",
	"toggle_bag_3": "F9",
	"toggle_bag_4": "F8",
	"name_plates": "V",
	"friendly_name_plates": "Shift+V",
}

static var _listed: Array[Dictionary] = []


static func apply() -> void:
	for action: String in DEFAULTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var event: InputEventKey = from_text(DEFAULTS[action])
		if event:
			InputMap.action_add_event(action, event)
	load_saved()


# Bindings.xml lists every binding in the order the stock frame shows them, under its headers.
static func listed() -> Array[Dictionary]:
	if not _listed.is_empty():
		return _listed
	var xml: XMLParser = XMLParser.new()
	if xml.open_buffer(WowAssets.archive.read(BINDINGS_XML)) != OK:
		return _listed
	while xml.read() == OK:
		if xml.get_node_type() != XMLParser.NODE_ELEMENT or xml.get_node_name() != "Binding":
			continue
		var header: String = xml.get_named_attribute_value_safe("header")
		if not header.is_empty():
			_listed.append({"header": header})
		var name: String = xml.get_named_attribute_value_safe("name")
		var action: String = action_of(name)
		if not action.is_empty():
			_listed.append({"name": name, "action": action})
	return _listed


# The stock names run the words together, so MOVEFORWARD is this client's move_forward action.
static func action_of(binding_name: String) -> String:
	for action: StringName in InputMap.get_actions():
		if String(action).replace("_", "").to_upper() == binding_name:
			return action
	return ""


# The key a binding holds, in the stock frame's shape, such as SHIFT-T.
static func binding_text(action: String, slot: int) -> String:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	var keys: Array[InputEventKey] = []
	for event: InputEvent in events:
		if event is InputEventKey:
			keys.append(event)
	if slot >= keys.size():
		return ""
	return to_text(keys[slot])


static func to_text(event: InputEventKey) -> String:
	var parts: PackedStringArray = []
	if event.alt_pressed:
		parts.append("ALT")
	if event.ctrl_pressed:
		parts.append("CTRL")
	if event.shift_pressed:
		parts.append("SHIFT")
	parts.append(OS.get_keycode_string(event.physical_keycode).to_upper())
	return "-".join(parts)


static func from_text(text: String) -> InputEventKey:
	var parts: PackedStringArray = text.replace("-", "+").split("+", false)
	if parts.is_empty():
		return null
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = OS.find_keycode_from_string(parts[parts.size() - 1])
	event.alt_pressed = _holds(parts, "ALT")
	event.ctrl_pressed = _holds(parts, "CTRL")
	event.shift_pressed = _holds(parts, "SHIFT")
	return event if event.physical_keycode != KEY_NONE else null


# Puts a key on a binding, taking it off whatever else held it, as the stock frame does.
static func bind(action: String, slot: int, event: InputEventKey) -> void:
	for other: StringName in InputMap.get_actions():
		for held: InputEvent in InputMap.action_get_events(other):
			if held is InputEventKey and to_text(held) == to_text(event):
				InputMap.action_erase_event(other, held)
	var keys: Array[InputEvent] = []
	for held: InputEvent in InputMap.action_get_events(action):
		if held is InputEventKey:
			keys.append(held)
	if slot < keys.size():
		InputMap.action_erase_event(action, keys[slot])
	InputMap.action_add_event(action, event)


# Takes the key off one of a binding's two slots.
static func unbind(action: String, slot: int) -> void:
	var keys: Array[InputEvent] = []
	for held: InputEvent in InputMap.action_get_events(action):
		if held is InputEventKey:
			keys.append(held)
	if slot < keys.size():
		InputMap.action_erase_event(action, keys[slot])


# Puts a binding back to the keys it held, which is how the window cancels.
static func set_keys(action: String, texts: PackedStringArray) -> void:
	if not InputMap.has_action(action):
		return
	for held: InputEvent in InputMap.action_get_events(action):
		if held is InputEventKey:
			InputMap.action_erase_event(action, held)
	for text: String in texts:
		var event: InputEventKey = from_text(text)
		if event:
			InputMap.action_add_event(action, event)


static func save() -> void:
	var saved: ConfigFile = ConfigFile.new()
	for entry: Dictionary in listed():
		if not entry.has("action"):
			continue
		var keys: PackedStringArray = []
		for slot: int in 2:
			keys.append(binding_text(entry["action"], slot))
		saved.set_value(SECTION, entry["action"], keys)
	saved.save(SETTINGS_PATH)


static func load_saved() -> void:
	var saved: ConfigFile = ConfigFile.new()
	if saved.load(SETTINGS_PATH) != OK:
		return
	for action: String in saved.get_section_keys(SECTION):
		if not InputMap.has_action(action):
			continue
		for held: InputEvent in InputMap.action_get_events(action):
			if held is InputEventKey:
				InputMap.action_erase_event(action, held)
		for text: String in saved.get_value(SECTION, action, PackedStringArray()):
			var event: InputEventKey = from_text(text)
			if event:
				InputMap.action_add_event(action, event)


static func _holds(parts: PackedStringArray, modifier: String) -> bool:
	for part: String in parts:
		if part.to_upper() == modifier:
			return true
	return false
