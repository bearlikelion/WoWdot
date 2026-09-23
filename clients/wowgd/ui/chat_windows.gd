class_name ChatWindows
extends RefCounted

## The tabs need lining up again, because a window was renamed, opened or closed.
signal layout_changed

enum MenuItem { RENAME = 1, NEW_WINDOW, REMOVE_WINDOW, FONT_SIZE, CHANNELS, SYSTEM, OTHER }

const SETTINGS_PATH: String = "user://chat_windows.cfg"
# CHAT_FONT_HEIGHTS from Fonts.xml.
const FONT_SIZES: Array[int] = [12, 14, 16, 18]
const DEFAULT_FONT_SIZE: int = 14
const ALL_CHANNELS: String = "*"
# NUM_CHAT_WINDOWS; General and the Combat Log are the first two.
const MAX_WINDOWS: int = 7
const FIXED_WINDOWS: int = 2
# ChatTypeGroup: which group each chat type files under.
const TYPE_GROUPS: Dictionary[WowSession.ChatType, String] = {
	WowSession.CHAT_SAY: "SAY", WowSession.CHAT_EMOTE: "SAY", WowSession.CHAT_TEXT_EMOTE: "SAY",
	WowSession.CHAT_YELL: "YELL", WowSession.CHAT_WHISPER: "WHISPER",
	WowSession.CHAT_WHISPER_INFORM: "WHISPER", WowSession.CHAT_PARTY: "PARTY",
	WowSession.CHAT_RAID: "PARTY", WowSession.CHAT_RAID_LEADER: "PARTY",
	WowSession.CHAT_RAID_WARNING: "PARTY", WowSession.CHAT_BATTLEGROUND: "PARTY",
	WowSession.CHAT_BATTLEGROUND_LEADER: "PARTY", WowSession.CHAT_GUILD: "GUILD",
	WowSession.CHAT_OFFICER: "GUILD", WowSession.CHAT_MONSTER_SAY: "CREATURE",
	WowSession.CHAT_MONSTER_YELL: "CREATURE", WowSession.CHAT_MONSTER_EMOTE: "CREATURE",
	WowSession.CHAT_MONSTER_WHISPER: "CREATURE", WowSession.CHAT_RAID_BOSS_EMOTE: "CREATURE",
	WowSession.CHAT_RAID_BOSS_WHISPER: "CREATURE", WowSession.CHAT_SYSTEM: "SYSTEM",
	WowSession.CHAT_AFK: "SYSTEM", WowSession.CHAT_DND: "SYSTEM",
}
# ChannelMenuChatTypeGroups and OtherMenuChatTypeGroups, each with the string that names it.
const CHANNEL_GROUPS: Dictionary[String, String] = {
	"SAY": "SAY", "YELL": "CHAT_MSG_YELL", "GUILD": "CHAT_MSG_GUILD",
	"WHISPER": "CHAT_MSG_WHISPER", "PARTY": "CHAT_MSG_PARTY",
}
const OTHER_GROUPS: Dictionary[String, String] = {
	"CREATURE": "CREATURE", "SKILL": "CHAT_MSG_SKILL", "LOOT": "LOOT",
}
# The stock client offers no toggle for these; here they can move to another window too.
const SYSTEM_GROUPS: Dictionary[String, String] = {"SYSTEM": "CHAT_MSG_SYSTEM"}
# FCF_OpenNewWindow: what a new window listens to.
const NEW_WINDOW_GROUPS: PackedStringArray = ["SAY", "YELL", "GUILD", "WHISPER", "PARTY", "CHANNEL"]
# What the General window listens to before anything is changed.
const GENERAL_GROUPS: PackedStringArray = [
	"SYSTEM", "SAY", "YELL", "WHISPER", "PARTY", "GUILD", "CREATURE", "CHANNEL", "SKILL", "LOOT",
]

var frames: Array[DockedChatFrame] = []

var _open_menu: Callable
var _ask_name: Callable
var _add_window: Callable
var _remove_window: Callable
var _character: String = ""


# open_menu takes the entries and a Callable for the chosen id; ask_name a prompt and its answer.
# add_window makes a docked window and returns it, remove_window takes one away again.
func _init(
	chat_frames: Array[DockedChatFrame], open_menu: Callable, ask_name: Callable,
	add_window: Callable, remove_window: Callable,
) -> void:
	frames = chat_frames
	_open_menu = open_menu
	_ask_name = ask_name
	_add_window = add_window
	_remove_window = remove_window
	for frame: DockedChatFrame in frames:
		frame.tab_menu_requested.connect(show_tab_menu.bind(frame))
	frames[0].message_groups = GENERAL_GROUPS
	frames[0].channels = [ALL_CHANNELS]


## ChatFrame_OnEvent's filter: the line goes to every window that shows its group and channel.
func add_line(text: String, color: Color, group: String, channel: String = "") -> void:
	for frame: DockedChatFrame in frames:
		if _shows(frame, group, channel):
			frame.add_message(text, color)


func add_chat(line: Dictionary) -> void:
	var chat_type: WowSession.ChatType = line["type"] as WowSession.ChatType
	var text: String = ChatFrame.format_line(line)
	var color: Color = ChatFrame.COLORS.get(chat_type, Color.WHITE)
	if chat_type == WowSession.CHAT_CHANNEL:
		add_line(text, color, "", line.get("channel", ""))
	else:
		add_line(text, color, TYPE_GROUPS.get(chat_type, "SYSTEM"))


func character() -> String:
	return _character


## Each character keeps its own window settings, as chat-cache.txt did.
func load_for(character: String) -> void:
	_character = character
	var settings: ConfigFile = ConfigFile.new()
	if settings.load(SETTINGS_PATH) != OK or not settings.has_section(character):
		return
	var count: int = clampi(settings.get_value(character, "windows", frames.size()), 0, MAX_WINDOWS)
	while frames.size() < count:
		_open_window("")
	for i: int in frames.size():
		var key: String = "window%d_" % (i + 1)
		var frame: DockedChatFrame = frames[i]
		frame.window_name = settings.get_value(character, key + "name", frame.window_name)
		frame.font_size = settings.get_value(character, key + "font_size", frame.font_size)
		frame.message_groups = settings.get_value(character, key + "groups", frame.message_groups)
		frame.channels = settings.get_value(character, key + "channels", frame.channels)
	layout_changed.emit()


# FCFOptionsDropDown_Initialize, a level at a time: submenus open as menus of their own.
func show_tab_menu(frame: DockedChatFrame) -> void:
	var entries: Array[Dictionary] = [
		{"text": WowStrings.get_text("RENAME_CHAT_WINDOW"), "id": MenuItem.RENAME},
		{
			"text": WowStrings.get_text("NEW_CHAT_WINDOW"), "id": MenuItem.NEW_WINDOW,
			"disabled": frames.size() >= MAX_WINDOWS,
		},
	]
	if frames.find(frame) >= FIXED_WINDOWS:
		entries.append({
			"text": WowStrings.get_text("CLOSE_CHAT_WINDOW"), "id": MenuItem.REMOVE_WINDOW,
		})
	entries.append_array([
		{"text": WowStrings.get_text("DISPLAY"), "title": true},
		{"text": WowStrings.get_text("FONT_SIZE"), "id": MenuItem.FONT_SIZE},
		{"text": WowStrings.get_text("FILTERS"), "title": true},
		{"text": WowStrings.get_text("CHANNELS"), "id": MenuItem.CHANNELS},
		{"text": WowStrings.get_text("SYSTEM_MESSAGES"), "id": MenuItem.SYSTEM},
		{"text": WowStrings.get_text("OTHER_MESSAGES"), "id": MenuItem.OTHER},
	])
	_open_menu.call(entries, func(id: int) -> void:
		match id as MenuItem:
			MenuItem.RENAME:
				_rename(frame)
			MenuItem.NEW_WINDOW:
				_ask_name.call(WowStrings.get_text("NAME_CHAT_WINDOW"), _on_new_window_named)
			MenuItem.REMOVE_WINDOW:
				frames.erase(frame)
				_remove_window.call(frame)
				layout_changed.emit()
				_save()
			MenuItem.FONT_SIZE:
				_show_font_menu.call_deferred(frame)
			MenuItem.CHANNELS:
				_show_filter_menu.call_deferred(frame, "CHANNELS", CHANNEL_GROUPS, true)
			MenuItem.SYSTEM:
				_show_filter_menu.call_deferred(frame, "SYSTEM_MESSAGES", SYSTEM_GROUPS, false)
			MenuItem.OTHER:
				_show_filter_menu.call_deferred(frame, "OTHER_MESSAGES", OTHER_GROUPS, false)
	)


func _on_new_window_named(window_name: String) -> void:
	_open_window(window_name.strip_edges())
	_save()


# FCF_OpenNewWindow: an unnamed window takes CHAT_NAME_TEMPLATE with its number.
func _open_window(window_name: String) -> void:
	if frames.size() >= MAX_WINDOWS:
		return
	var frame: DockedChatFrame = _add_window.call()
	frame.window_name = window_name if not window_name.is_empty() \
			else WowStrings.get_text("CHAT_NAME_TEMPLATE") % frames.size()
	frame.message_groups = NEW_WINDOW_GROUPS
	frame.channels = []
	frame.tab_menu_requested.connect(show_tab_menu.bind(frame))
	layout_changed.emit()


func _shows(frame: DockedChatFrame, group: String, channel: String) -> bool:
	if not channel.is_empty():
		return ALL_CHANNELS in frame.channels or channel in frame.channels
	return group in frame.message_groups


func _rename(frame: DockedChatFrame) -> void:
	_ask_name.call(WowStrings.get_text("NAME_CHAT_WINDOW"), func(window_name: String) -> void:
		if not window_name.strip_edges().is_empty():
			frame.window_name = window_name.strip_edges()
			layout_changed.emit()
			_save()
	)


func _show_font_menu(frame: DockedChatFrame) -> void:
	var current: int = frame.font_size if frame.font_size > 0 else DEFAULT_FONT_SIZE
	var entries: Array[Dictionary] = []
	for size: int in FONT_SIZES:
		entries.append({
			"text": WowStrings.get_text("FONT_SIZE_TEMPLATE") % size, "id": size,
			"checked": size == current,
		})
	_open_menu.call(entries, func(size: int) -> void:
		frame.font_size = size
		_save()
	)


# FCFDropDown_LoadChatTypes and, for Channels, FCFDropDown_LoadChannels: a click toggles one.
func _show_filter_menu(
	frame: DockedChatFrame, title_key: String, groups: Dictionary[String, String],
	with_channels: bool,
) -> void:
	var entries: Array[Dictionary] = [{"text": WowStrings.get_text(title_key), "title": true}]
	var keys: Array[String] = []
	for group: String in groups:
		keys.append(group)
		entries.append({
			"text": WowStrings.get_text(groups[group]), "id": keys.size(),
			"checked": group in frame.message_groups,
		})
	var channel_ids: Dictionary[int, String] = {}
	if with_channels:
		for channel: String in Channels.joined:
			channel_ids[keys.size() + channel_ids.size() + 1] = channel
			entries.append({
				"text": channel, "id": keys.size() + channel_ids.size(),
				"checked": _shows(frame, "", channel),
			})
	_open_menu.call(entries, func(id: int) -> void:
		if channel_ids.has(id):
			_toggle_channel(frame, channel_ids[id])
		elif id >= 1 and id <= keys.size():
			_toggle_group(frame, keys[id - 1])
		_save()
	)


func _toggle_group(frame: DockedChatFrame, group: String) -> void:
	var groups: PackedStringArray = frame.message_groups.duplicate()
	if group in groups:
		groups.remove_at(groups.find(group))
	else:
		groups.append(group)
	frame.message_groups = groups


# Turning one channel off in a window that shows them all lists the rest explicitly.
func _toggle_channel(frame: DockedChatFrame, channel: String) -> void:
	var listed: PackedStringArray = frame.channels.duplicate()
	if ALL_CHANNELS in listed:
		listed = Channels.joined.duplicate()
	if channel in listed:
		listed.remove_at(listed.find(channel))
	else:
		listed.append(channel)
	frame.channels = listed


func _save() -> void:
	if _character.is_empty():
		return
	var settings: ConfigFile = ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value(_character, "windows", frames.size())
	for i: int in frames.size():
		var key: String = "window%d_" % (i + 1)
		settings.set_value(_character, key + "name", frames[i].window_name)
		settings.set_value(_character, key + "font_size", frames[i].font_size)
		settings.set_value(_character, key + "groups", frames[i].message_groups)
		settings.set_value(_character, key + "channels", frames[i].channels)
	settings.save(SETTINGS_PATH)
