class_name ChatFrame
extends WowScrollingMessageFrame

# GlobalStrings key stem per chat type: CHAT_<stem>_GET formats lines, CHAT_<stem>_SEND the header.
const TYPE_KEYS: Dictionary[WowSession.ChatType, String] = {
	WowSession.CHAT_SAY: "SAY", WowSession.CHAT_PARTY: "PARTY", WowSession.CHAT_RAID: "RAID",
	WowSession.CHAT_GUILD: "GUILD", WowSession.CHAT_OFFICER: "OFFICER",
	WowSession.CHAT_YELL: "YELL", WowSession.CHAT_WHISPER: "WHISPER",
	WowSession.CHAT_WHISPER_INFORM: "WHISPER_INFORM", WowSession.CHAT_EMOTE: "EMOTE",
	WowSession.CHAT_MONSTER_SAY: "MONSTER_SAY", WowSession.CHAT_MONSTER_YELL: "MONSTER_YELL",
	WowSession.CHAT_MONSTER_WHISPER: "MONSTER_WHISPER",
	WowSession.CHAT_RAID_BOSS_WHISPER: "MONSTER_WHISPER", WowSession.CHAT_CHANNEL: "CHANNEL",
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
}
# Player names in these lines are shown as [Name] links, as ChatFrame_OnEvent writes them.
const PLAYER_TYPES: Array[WowSession.ChatType] = [
	WowSession.CHAT_SAY, WowSession.CHAT_PARTY, WowSession.CHAT_RAID, WowSession.CHAT_GUILD,
	WowSession.CHAT_OFFICER, WowSession.CHAT_YELL, WowSession.CHAT_WHISPER,
	WowSession.CHAT_WHISPER_INFORM, WowSession.CHAT_CHANNEL,
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
}
# Chat types the edit box keeps between messages; whispers and emotes fall back to the last one.
const STICKY: Array[WowSession.ChatType] = [
	WowSession.CHAT_SAY, WowSession.CHAT_YELL, WowSession.CHAT_PARTY, WowSession.CHAT_GUILD,
	WowSession.CHAT_OFFICER, WowSession.CHAT_RAID,
]
const HISTORY_LINES: int = 32
# DEFAULT_CHATFRAME_ALPHA: the background only shows while the mouse is over the chat.
const HOVER_ALPHA: float = 0.25
# ChatEdit_UpdateHeader: SetTextInsets(15 + header width, 13, 0, 0).
const INSET_LEFT: float = 15.0
const INSET_RIGHT: float = 13.0

var _chat_type: WowSession.ChatType = WowSession.CHAT_SAY
var _sticky_type: WowSession.ChatType = WowSession.CHAT_SAY
var _whisper_target: String = ""
var _last_whisperer: String = ""
var _history: PackedStringArray = []
var _history_index: int = -1
var _insets: StyleBoxEmpty = StyleBoxEmpty.new()

@onready var _edit_box: LineEdit = %ChatFrameEditBox
@onready var _header: Label = %ChatFrameEditBoxHeader
@onready var _background: TextureRect = %ChatFrame1Background


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_entered.connect(func() -> void: _background.self_modulate.a = HOVER_ALPHA)
	mouse_exited.connect(func() -> void: _background.self_modulate.a = 0.0)
	_background.self_modulate = Color(0.0, 0.0, 0.0, 0.0)
	%ChatFrame1UpButton.pressed.connect(scroll_up)
	%ChatFrame1DownButton.pressed.connect(scroll_down)
	%ChatFrame1BottomButton.pressed.connect(scroll_to_bottom)
	%ChatFrame1TabText.text = WowStrings.get_text("GENERAL")
	for unused: String in [
		"ChatFrame1ResizeTopLeft", "ChatFrame1ResizeTopRight", "ChatFrame1ResizeBottomLeft",
		"ChatFrame1ResizeBottomRight", "ChatFrame1ResizeTop", "ChatFrame1ResizeBottom",
		"ChatFrame1ResizeLeft", "ChatFrame1ResizeRight", "ChatFrameEditBoxLanguage",
		"ChatFrame1TabDropDown",
	]:
		(get_node("%" + unused) as CanvasItem).hide()
	_edit_box.theme_type_variation = &"ChatEditBox"
	# SetTextInsets moves with the header's width, so this one style is the edit box's own.
	for state: StringName in [&"normal", &"focus", &"read_only"]:
		_edit_box.add_theme_stylebox_override(state, _insets)
	_edit_box.text_submitted.connect(_on_text_submitted)
	_edit_box.text_changed.connect(_on_text_changed)
	_edit_box.gui_input.connect(_on_edit_box_input)
	_edit_box.hide()
	WowClient.session.chat_received.connect(_on_chat_received)


func _unhandled_input(event: InputEvent) -> void:
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
	_whisper_target = ""
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


func format_line(line: Dictionary) -> String:
	var chat_type: WowSession.ChatType = line["type"] as WowSession.ChatType
	var sender: String = line.get("sender_name", "")
	var text: String = line.get("text", "")
	match chat_type:
		WowSession.CHAT_SYSTEM, WowSession.CHAT_TEXT_EMOTE:
			return text
		WowSession.CHAT_MONSTER_EMOTE, WowSession.CHAT_RAID_BOSS_EMOTE:
			return text.replace("%s", sender)
	var who: String = "[%s]" % sender if chat_type in PLAYER_TYPES else sender
	var key: String = "CHAT_%s_GET" % TYPE_KEYS.get(chat_type, "SAY")
	var header: String = WowStrings.get_text(key, "%s: ")
	if chat_type == WowSession.CHAT_CHANNEL:
		header = "[%s] %s" % [line.get("channel", ""), header]
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
	else:
		return false
	return true


func _on_text_submitted(text: String) -> void:
	var message: String = _take_command(text.strip_edges()).strip_edges()
	var chat_type: WowSession.ChatType = _chat_type
	var target: String = _whisper_target
	close()
	if message.is_empty():
		return
	_history.append(text.strip_edges())
	if _history.size() > HISTORY_LINES:
		_history.remove_at(0)
	if _run_party_command(message):
		return
	if message.begins_with("/"):
		add_message(WowStrings.get_text("HELP_TEXT_SIMPLE"), COLORS[WowSession.CHAT_SYSTEM])
		return
	if chat_type in STICKY:
		_sticky_type = chat_type
	WowClient.session.send_chat(chat_type, message, target)


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
