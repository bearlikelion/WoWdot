@tool
class_name ChatFrame
extends DockedChatFrame

signal emote_requested(text_emote: int)
signal ticket_requested(text: String)
signal item_ref_requested(link: String)
signal menu_requested(entries: Array[Dictionary], chosen: Callable)
signal macro_requested

enum ChatMenuItem { SAY = 1, PARTY, GUILD, YELL, WHISPER, EMOTE, REPLY, VOICE_EMOTE, MACRO }

# GlobalStrings key stem per chat type: CHAT_<stem>_GET formats lines, CHAT_<stem>_SEND the header.
const TYPE_KEYS: Dictionary[WowSession.ChatType, String] = {
	WowSession.CHAT_SAY: "SAY", WowSession.CHAT_PARTY: "PARTY", WowSession.CHAT_RAID: "RAID",
	WowSession.CHAT_GUILD: "GUILD", WowSession.CHAT_OFFICER: "OFFICER",
	WowSession.CHAT_YELL: "YELL", WowSession.CHAT_WHISPER: "WHISPER",
	WowSession.CHAT_WHISPER_INFORM: "WHISPER_INFORM", WowSession.CHAT_EMOTE: "EMOTE",
	WowSession.CHAT_MONSTER_SAY: "MONSTER_SAY", WowSession.CHAT_MONSTER_YELL: "MONSTER_YELL",
	WowSession.CHAT_MONSTER_WHISPER: "MONSTER_WHISPER",
	WowSession.CHAT_RAID_BOSS_WHISPER: "MONSTER_WHISPER", WowSession.CHAT_CHANNEL: "CHANNEL",
	WowSession.CHAT_AFK: "AFK", WowSession.CHAT_DND: "DND",
	WowSession.CHAT_RAID_LEADER: "RAID_LEADER", WowSession.CHAT_RAID_WARNING: "RAID_WARNING",
	WowSession.CHAT_BATTLEGROUND: "BATTLEGROUND",
	WowSession.CHAT_BATTLEGROUND_LEADER: "BATTLEGROUND_LEADER",
}
# ChatTypeInfo colours from the stock chat configuration.
const COLORS: Dictionary[WowSession.ChatType, Color] = {
	WowSession.CHAT_SAY: Color(1.0, 1.0, 1.0),
	WowSession.CHAT_PARTY: Color(0.67, 0.67, 1.0),
	WowSession.CHAT_RAID: Color(1.0, 0.5, 0.0),
	WowSession.CHAT_GUILD: Color(0.25, 1.0, 0.25),
	WowSession.CHAT_OFFICER: Color(0.25, 0.75, 0.25),
	WowSession.CHAT_YELL: Color(1.0, 0.25, 0.25),
	WowSession.CHAT_WHISPER: Color(1.0, 0.5, 1.0),
	WowSession.CHAT_WHISPER_INFORM: Color(1.0, 0.5, 1.0),
	WowSession.CHAT_EMOTE: Color(1.0, 0.5, 0.25),
	WowSession.CHAT_TEXT_EMOTE: Color(1.0, 0.5, 0.25),
	WowSession.CHAT_SYSTEM: Color(1.0, 1.0, 0.0),
	WowSession.CHAT_MONSTER_SAY: Color(1.0, 1.0, 0.62),
	WowSession.CHAT_MONSTER_YELL: Color(1.0, 0.25, 0.25),
	WowSession.CHAT_MONSTER_EMOTE: Color(1.0, 0.5, 0.25),
	WowSession.CHAT_MONSTER_WHISPER: Color(1.0, 0.5, 1.0),
	WowSession.CHAT_RAID_BOSS_WHISPER: Color(1.0, 0.5, 1.0),
	WowSession.CHAT_RAID_BOSS_EMOTE: Color(1.0, 0.5, 0.25),
	WowSession.CHAT_CHANNEL: Color(1.0, 0.75, 0.75),
	WowSession.CHAT_AFK: Color(1.0, 0.5, 1.0),
	WowSession.CHAT_DND: Color(1.0, 0.5, 1.0),
	WowSession.CHAT_RAID_LEADER: Color(1.0, 0.28, 0.04),
	WowSession.CHAT_RAID_WARNING: Color(1.0, 0.28, 0.0),
	WowSession.CHAT_BATTLEGROUND: Color(1.0, 0.5, 0.0),
	WowSession.CHAT_BATTLEGROUND_LEADER: Color(1.0, 0.86, 0.72),
}
# Player names in these lines are shown as [Name] links, as ChatFrame_OnEvent writes them.
const PLAYER_TYPES: Array[WowSession.ChatType] = [
	WowSession.CHAT_SAY, WowSession.CHAT_PARTY, WowSession.CHAT_RAID, WowSession.CHAT_GUILD,
	WowSession.CHAT_OFFICER, WowSession.CHAT_YELL, WowSession.CHAT_WHISPER,
	WowSession.CHAT_WHISPER_INFORM, WowSession.CHAT_CHANNEL, WowSession.CHAT_AFK,
	WowSession.CHAT_DND, WowSession.CHAT_RAID_LEADER, WowSession.CHAT_RAID_WARNING,
	WowSession.CHAT_BATTLEGROUND, WowSession.CHAT_BATTLEGROUND_LEADER,
]
const COMMANDS: Dictionary[String, WowSession.ChatType] = {
	"/s": WowSession.CHAT_SAY, "/say": WowSession.CHAT_SAY,
	"/y": WowSession.CHAT_YELL, "/yell": WowSession.CHAT_YELL,
	"/e": WowSession.CHAT_EMOTE, "/em": WowSession.CHAT_EMOTE, "/me": WowSession.CHAT_EMOTE,
	"/emote": WowSession.CHAT_EMOTE,
	"/p": WowSession.CHAT_PARTY, "/party": WowSession.CHAT_PARTY,
	"/g": WowSession.CHAT_GUILD, "/guild": WowSession.CHAT_GUILD,
	"/o": WowSession.CHAT_OFFICER, "/officer": WowSession.CHAT_OFFICER,
	"/ra": WowSession.CHAT_RAID, "/raid": WowSession.CHAT_RAID,
	"/w": WowSession.CHAT_WHISPER, "/whisper": WowSession.CHAT_WHISPER,
	"/t": WowSession.CHAT_WHISPER, "/tell": WowSession.CHAT_WHISPER,
	"/rw": WowSession.CHAT_RAID_WARNING, "/bg": WowSession.CHAT_BATTLEGROUND,
	"/afk": WowSession.CHAT_AFK, "/dnd": WowSession.CHAT_DND,
}

const GUILD_COMMANDS: Dictionary[String, String] = {
	"/ginvite": "CMSG_GUILD_INVITE", "/guildinvite": "CMSG_GUILD_INVITE",
	"/gremove": "CMSG_GUILD_REMOVE", "/guildremove": "CMSG_GUILD_REMOVE",
	"/gpromote": "CMSG_GUILD_PROMOTE", "/guildpromote": "CMSG_GUILD_PROMOTE",
	"/gdemote": "CMSG_GUILD_DEMOTE", "/guilddemote": "CMSG_GUILD_DEMOTE",
	"/gmotd": "CMSG_GUILD_MOTD", "/guildmotd": "CMSG_GUILD_MOTD",
	"/gquit": "CMSG_GUILD_LEAVE", "/guildleave": "CMSG_GUILD_LEAVE",
}
# Chat types the edit box keeps between messages; whispers and emotes fall back to the last one.
const STICKY: Array[WowSession.ChatType] = [
	WowSession.CHAT_SAY, WowSession.CHAT_YELL, WowSession.CHAT_PARTY, WowSession.CHAT_GUILD,
	WowSession.CHAT_OFFICER, WowSession.CHAT_RAID, WowSession.CHAT_CHANNEL,
]
const HISTORY_LINES: int = 32
# EmoteList and TextEmoteSpeechList in ChatFrame.lua: the emotes that animate and those that speak.
const EMOTE_MENU: PackedStringArray = [
	"WAVE", "BOW", "DANCE", "APPLAUD", "BEG", "CHICKEN", "CRY", "EAT", "FLEX", "KISS", "LAUGH",
	"POINT", "ROAR", "RUDE", "SALUTE", "SHY", "TALK", "STAND", "SIT", "SLEEP", "KNEEL",
]
const VOICE_MENU: PackedStringArray = [
	"HELPME", "INCOMING", "CHARGE", "FLEE", "ATTACKMYTARGET", "OOM", "FOLLOW", "WAIT", "HEALME",
	"CHEER", "OPENFIRE", "RASP", "HELLO", "BYE", "NOD", "NO", "THANK", "WELCOME", "CONGRATULATE",
	"FLIRT", "JOKE", "TRAIN",
]
# ChatMenu_SetChatType: each chat entry opens the edit box on its slash command.
const MENU_COMMANDS: Dictionary[ChatMenuItem, String] = {
	ChatMenuItem.SAY: "/s ", ChatMenuItem.PARTY: "/p ", ChatMenuItem.GUILD: "/g ",
	ChatMenuItem.YELL: "/y ", ChatMenuItem.WHISPER: "/w ",
}
# ChatEdit_UpdateHeader: SetTextInsets(15 + header width, 13, 0, 0).
const INSET_LEFT: float = 15.0
const INSET_RIGHT: float = 13.0

var _chat_type: WowSession.ChatType = WowSession.CHAT_SAY
var _sticky_type: WowSession.ChatType = WowSession.CHAT_SAY
var _whisper_target: String = ""
var _sticky_channel: String = ""
var _last_whisperer: String = ""
var _history: PackedStringArray = []
var _history_index: int = -1
# Links in the edit box by the [Name] it shows for each, swapped back in when sending.
var _links: Dictionary[String, String] = {}
var _insets: StyleBoxEmpty = StyleBoxEmpty.new()

@onready var _edit_box: LineEdit = %ChatFrameEditBox
@onready var _header: Label = %ChatFrameEditBoxHeader


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	WowClient.macros.line_requested.connect(_on_text_submitted)
	window_name = WowStrings.get_text("GENERAL")
	%ChatFrameEditBoxLanguage.hide()
	_edit_box.theme_type_variation = &"ChatEditBox"
	# SetTextInsets moves with the header's width, so this one style is the edit box's own.
	for state: StringName in [&"normal", &"focus", &"read_only"]:
		_edit_box.add_theme_stylebox_override(state, _insets)
	_edit_box.text_submitted.connect(_on_text_submitted)
	_edit_box.text_changed.connect(_on_text_changed)
	_edit_box.gui_input.connect(_on_edit_box_input)
	_edit_box.hide()
	WowClient.session.chat_received.connect(_on_chat_received)
	link_clicked.connect(_on_link_clicked)
	%ChatFrameMenuButton.pressed.connect(_open_chat_menu)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if _edit_box.visible or not event.is_pressed() or event.is_echo():
		return
	var key: InputEventKey = event as InputEventKey
	if event.is_action_pressed("chat"):
		open()
	elif key and key.unicode == "/".unicode_at(0):
		open("/")
	elif event.is_action_pressed("reply_whisper") and not _last_whisperer.is_empty():
		open_whisper(_last_whisperer)
	else:
		return
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll_up()
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll_down()
			accept_event()


func open(prefill: String = "") -> void:
	_chat_type = _sticky_type
	_whisper_target = _sticky_channel if _chat_type == WowSession.CHAT_CHANNEL else ""
	_show_edit_box(prefill)


func open_whisper(target: String) -> void:
	_chat_type = WowSession.CHAT_WHISPER
	_whisper_target = target
	_show_edit_box("")


func close() -> void:
	_edit_box.clear()
	_edit_box.release_focus()
	_edit_box.hide()
	_history_index = -1
	_links.clear()


# ChatEdit_InsertLink: false when the edit box is not open to take it.
func insert_link(link: String) -> bool:
	var start: int = link.find("|h[")
	var end: int = link.find("]|h", start)
	if not _edit_box.visible or start < 0 or end < 0:
		return false
	var shown: String = link.substr(start + 2, end - start - 1)
	_links[shown] = link
	_edit_box.insert_text_at_caret(shown)
	return true


func format_line(line: Dictionary) -> String:
	var chat_type: WowSession.ChatType = line["type"] as WowSession.ChatType
	var sender: String = line.get("sender_name", "")
	var text: String = line.get("text", "")
	match chat_type:
		WowSession.CHAT_SYSTEM, WowSession.CHAT_TEXT_EMOTE:
			return text
		WowSession.CHAT_MONSTER_EMOTE, WowSession.CHAT_RAID_BOSS_EMOTE:
			return text.replace("%s", sender)
	var who: String = "|Hplayer:%s|h[%s]|h" % [sender, sender] if chat_type in PLAYER_TYPES \
			else sender
	var key: String = "CHAT_%s_GET" % TYPE_KEYS.get(chat_type, "SAY")
	var header: String = WowStrings.get_text(key, "%s: ")
	if chat_type == WowSession.CHAT_CHANNEL:
		var channel_name: String = line.get("channel", "")
		var number: int = Channels.number_of(channel_name)
		header = "[%s%s] %s" % ["%d. " % number if number > 0 else "", channel_name, header]
	return header.replace("%s", who) + text


func _show_edit_box(prefill: String) -> void:
	_edit_box.text = prefill
	_edit_box.show()
	_edit_box.grab_focus()
	_edit_box.caret_column = prefill.length()
	_update_header()


func _update_header() -> void:
	var header: String = WowStrings.get_text("CHAT_%s_SEND" % TYPE_KEYS[_chat_type], "")
	if _chat_type == WowSession.CHAT_WHISPER:
		header = header.replace("%s", _whisper_target)
	elif _chat_type == WowSession.CHAT_CHANNEL:
		header = "[%d. %s]: " % [Channels.number_of(_whisper_target), _whisper_target]
	elif _chat_type == WowSession.CHAT_EMOTE:
		var session: WowSession = WowClient.session
		header = header.replace("%s", session.get_object_name(session.get_player_guid()))
	_header.text = header
	_header.self_modulate = COLORS.get(_chat_type, Color.WHITE)
	_edit_box.self_modulate = COLORS.get(_chat_type, Color.WHITE)
	var font: Font = _header.get_theme_font("font")
	var font_size: int = _header.get_theme_font_size("font_size")
	var width: float = font.get_string_size(header, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_insets.content_margin_left = INSET_LEFT + width
	_insets.content_margin_right = INSET_RIGHT


# ChatEdit_OnSpacePressed: a leading "/y " or "/w Name " switches the chat type as it is typed.
func _on_text_changed(text: String) -> void:
	var rest: String = _take_command(text)
	if rest != text:
		_edit_box.text = rest
		_edit_box.caret_column = rest.length()
		_update_header()


# Switches the chat type for a known leading command and returns the text after it, else the text.
func _take_command(text: String) -> String:
	if not text.begins_with("/") or not text.contains(" "):
		return text
	var parts: PackedStringArray = text.split(" ", true, 1)
	var command: String = parts[0].to_lower()
	var channel_name: String = Channels.name_at(command.substr(1).to_int())
	if not channel_name.is_empty():
		_chat_type = WowSession.CHAT_CHANNEL
		_whisper_target = channel_name
		return parts[1]
	if not COMMANDS.has(command):
		return text
	var rest: String = parts[1]
	if COMMANDS[command] == WowSession.CHAT_WHISPER:
		var words: PackedStringArray = rest.split(" ", true, 1)
		if words.size() < 2 or words[0].is_empty():
			return text
		_whisper_target = words[0]
		rest = words[1]
	_chat_type = COMMANDS[command]
	return rest


# SlashCmdList GUILD_INVITE, GUILD_REMOVE, GUILD_PROMOTE, GUILD_DEMOTE, GUILD_MOTD and GUILD_QUIT.
func _run_guild_command(message: String) -> bool:
	var words: PackedStringArray = message.split(" ", false, 1)
	var opcode: String = GUILD_COMMANDS.get(words[0].to_lower(), "")
	var rest: String = words[1].strip_edges() if words.size() > 1 else ""
	if opcode.is_empty() or (rest.is_empty() and opcode != "CMSG_GUILD_LEAVE"):
		return false
	FriendsFrame.send_command(opcode, rest)
	return true


# SlashCmdList INVITE, UNINVITE and LEAVE.
func _run_party_command(message: String) -> bool:
	var words: PackedStringArray = message.split(" ", false, 1)
	var command: String = words[0].to_lower()
	var player_name: String = words[1].strip_edges() if words.size() > 1 else ""
	if command in ["/invite", "/inv"] and not player_name.is_empty():
		PartyFrame.invite(player_name)
	elif command in ["/uninvite", "/u", "/un", "/kick"] and not player_name.is_empty():
		PartyFrame.uninvite(player_name)
	elif command == "/leave":
		PartyFrame.leave()
	elif command in ["/readycheck", "/rc"]:
		PartyFrame.start_ready_check()
	else:
		return false
	return true


func _on_text_submitted(text: String) -> void:
	var message: String = _take_command(text.strip_edges()).strip_edges()
	for shown: String in _links:
		message = message.replace(shown, _links[shown])
	var chat_type: WowSession.ChatType = _chat_type
	var target: String = _whisper_target
	close()
	# A bare /afk or /dnd toggles the state with the server's default message.
	if message.to_lower() in ["/afk", "/dnd"]:
		WowClient.session.send_chat(COMMANDS[message.to_lower()], "")
		return
	if message.is_empty():
		return
	_history.append(text.strip_edges())
	if _history.size() > HISTORY_LINES:
		_history.remove_at(0)
	if text.begins_with("/") and _run_channel_command(text.strip_edges()):
		return
	if _run_party_command(message):
		return
	if _run_guild_command(message):
		return
	if text.begins_with("/") and _send_emote(text.strip_edges()):
		return
	if message.begins_with("/"):
		add_message(WowStrings.get_text("HELP_TEXT_SIMPLE"), COLORS[WowSession.CHAT_SYSTEM])
		return
	if chat_type in STICKY:
		_sticky_type = chat_type
		_sticky_channel = target
	WowClient.session.send_chat(chat_type, message, target)


# /join and /leave take a channel.
func _run_channel_command(text: String) -> bool:
	var parts: PackedStringArray = text.substr(1).split(" ", false)
	if parts.is_empty():
		return false
	var command: String = parts[0].to_lower()
	var rest: PackedStringArray = parts.slice(1)
	if command in ["join", "j", "chat"] and not rest.is_empty():
		Channels.join(rest[0], rest[1] if rest.size() > 1 else "")
		return true
	if command in ["random", "rand", "rnd", "roll"]:
		var bounds: PackedByteArray = []
		bounds.resize(8)
		bounds.encode_u32(0, rest[0].to_int() if rest.size() > 1 else 1)
		bounds.encode_u32(4, rest[rest.size() - 1].to_int() if not rest.is_empty() else 100)
		WowClient.session.send_packet("MSG_RANDOM_ROLL", bounds)
		return true
	if command == "ticket":
		if rest.is_empty():
			WowClient.session.send_packet("CMSG_GMTICKET_GETTICKET", PackedByteArray())
		elif rest[0].to_lower() == "delete":
			WowClient.session.send_packet("CMSG_GMTICKET_DELETETICKET", PackedByteArray())
		else:
			ticket_requested.emit(" ".join(rest))
		return true
	if command == "raidinfo":
		WowClient.session.send_packet("CMSG_REQUEST_RAID_INFO", PackedByteArray())
		return true
	if command == "played":
		WowClient.session.send_packet("CMSG_PLAYED_TIME", PackedByteArray())
		return true
	if command == "who":
		ServerNotices.ask_who(rest)
		return true
	if Channels.run_command(command, rest):
		return true
	# A bare /leave still leaves the party, so this only takes the ones naming a channel.
	if command in ["leave", "chatleave", "chatexit"] and not rest.is_empty():
		var leaving: String = Channels.name_at(rest[0].to_int()) if rest[0].is_valid_int() \
		else rest[0]
		if Channels.number_of(leaving) == 0:
			return false
		Channels.leave(leaving)
		return true
	return false


# Any EmotesText token works as its own slash command, as /dance and /wave do.
func _send_emote(text: String) -> bool:
	var token: String = text.substr(1).split(" ")[0]
	var text_emote: int = Emotes.find(token)
	if text_emote == 0:
		return false
	emote_requested.emit(text_emote)
	return true


func _on_edit_box_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_edit_box.accept_event()
		close()
	elif event.is_action_pressed("ui_up") and not _history.is_empty():
		_edit_box.accept_event()
		var previous: int = _history_index - 1 if _history_index > 0 else _history.size() - 1
		_history_index = clampi(previous, 0, _history.size() - 1)
		_edit_box.text = _history[_history_index]
		_edit_box.caret_column = _edit_box.text.length()
	elif event.is_action_pressed("ui_down") and _history_index >= 0:
		_edit_box.accept_event()
		_history_index += 1
		_edit_box.text = _history[_history_index] if _history_index < _history.size() else ""
		_edit_box.caret_column = _edit_box.text.length()


func _on_chat_received(line: Dictionary) -> void:
	var chat_type: WowSession.ChatType = line["type"] as WowSession.ChatType
	if chat_type == WowSession.CHAT_WHISPER:
		_last_whisperer = line.get("sender_name", "")
	add_message(format_line(line), COLORS.get(chat_type, Color.WHITE))


# SetItemRef: a name whispers, or asks /who with Shift; an item shows ItemRefTooltip.
func _on_link_clicked(link: String) -> void:
	var parts: PackedStringArray = link.split(":")
	parts.resize(4)
	if parts[0] == "player" and not parts[1].is_empty():
		if Input.is_key_pressed(KEY_SHIFT):
			ServerNotices.ask_who([parts[1]])
		else:
			open_whisper(parts[1])
	elif parts[0] == "item":
		var item_entry: int = parts[1].to_int()
		if Input.is_key_pressed(KEY_SHIFT) \
		and insert_link(Inventory.item_link(item_entry, parts[2].to_int(), parts[3].to_int())):
			return
		if Input.is_key_pressed(KEY_CTRL) and ItemButton.dress_up.is_valid():
			ItemButton.dress_up.call(item_entry)
		else:
			item_ref_requested.emit(link)


# ChatMenu_OnLoad; the stock Emote and Voice Emote submenus open as a menu of their own here.
func _open_chat_menu() -> void:
	var entries: Array[Dictionary] = []
	for item: Array in [
		[ChatMenuItem.SAY, "SAY_MESSAGE"], [ChatMenuItem.PARTY, "PARTY_MESSAGE"],
		[ChatMenuItem.GUILD, "GUILD_MESSAGE"], [ChatMenuItem.YELL, "YELL_MESSAGE"],
		[ChatMenuItem.WHISPER, "WHISPER_MESSAGE"], [ChatMenuItem.EMOTE, "EMOTE_MESSAGE"],
		[ChatMenuItem.REPLY, "REPLY_MESSAGE"], [ChatMenuItem.VOICE_EMOTE, "VOICEMACRO_LABEL"],
		[ChatMenuItem.MACRO, "MACRO"],
	]:
		entries.append({"text": WowStrings.get_text(item[1]), "id": item[0]})
	menu_requested.emit(entries, _on_chat_menu_chosen)


func _on_chat_menu_chosen(id: int) -> void:
	var item: ChatMenuItem = id as ChatMenuItem
	if MENU_COMMANDS.has(item):
		open(MENU_COMMANDS[item])
	elif item == ChatMenuItem.EMOTE:
		_open_emote_menu.call_deferred(EMOTE_MENU)
	elif item == ChatMenuItem.VOICE_EMOTE:
		_open_emote_menu.call_deferred(VOICE_MENU)
	elif item == ChatMenuItem.REPLY and not _last_whisperer.is_empty():
		open_whisper(_last_whisperer)
	elif item == ChatMenuItem.MACRO:
		macro_requested.emit()


# OnMenuLoad: each emote listed by its slash command, sorted as TextEmoteSort does.
func _open_emote_menu(tokens: PackedStringArray) -> void:
	var entries: Array[Dictionary] = []
	for token: String in tokens:
		var text_emote: int = Emotes.find(token)
		if text_emote != 0:
			entries.append({"text": _emote_command(token), "id": text_emote})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["text"] < b["text"])
	menu_requested.emit(entries, func(text_emote: int) -> void: emote_requested.emit(text_emote))


func _emote_command(token: String) -> String:
	var i: int = 1
	while WowStrings.has_text("EMOTE%d_TOKEN" % i):
		if WowStrings.get_text("EMOTE%d_TOKEN" % i) == token:
			return WowStrings.get_text("EMOTE%d_CMD1" % i)
		i += 1
	return token.to_lower()
