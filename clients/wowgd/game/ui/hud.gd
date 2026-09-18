class_name Hud
extends Control

const CHAT_FORMATS: Dictionary[WowSession.ChatType, String] = {
	WowSession.CHAT_SAY: "{name} says: {text}",
	WowSession.CHAT_PARTY: "[Party] {name}: {text}",
	WowSession.CHAT_RAID: "[Raid] {name}: {text}",
	WowSession.CHAT_GUILD: "[Guild] {name}: {text}",
	WowSession.CHAT_OFFICER: "[Officer] {name}: {text}",
	WowSession.CHAT_YELL: "{name} yells: {text}",
	WowSession.CHAT_WHISPER: "{name} whispers: {text}",
	WowSession.CHAT_WHISPER_INFORM: "To {name}: {text}",
	WowSession.CHAT_EMOTE: "{name} {text}",
	WowSession.CHAT_TEXT_EMOTE: "{text}",
	WowSession.CHAT_SYSTEM: "{text}",
	WowSession.CHAT_MONSTER_SAY: "{name} says: {text}",
	WowSession.CHAT_MONSTER_YELL: "{name} yells: {text}",
	WowSession.CHAT_MONSTER_EMOTE: "{name} {text}",
	WowSession.CHAT_CHANNEL: "[{channel}] {name}: {text}",
	WowSession.CHAT_MONSTER_WHISPER: "{name} whispers: {text}",
	WowSession.CHAT_RAID_BOSS_WHISPER: "{name} whispers: {text}",
	WowSession.CHAT_RAID_BOSS_EMOTE: "{name} {text}",
}
const CHAT_COLORS: Dictionary[WowSession.ChatType, Color] = {
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
	WowSession.CHAT_CHANNEL: Color(1.0, 0.75, 0.75),
	WowSession.CHAT_MONSTER_WHISPER: Color(1.0, 0.5, 1.0),
	WowSession.CHAT_RAID_BOSS_WHISPER: Color(1.0, 0.5, 1.0),
	WowSession.CHAT_RAID_BOSS_EMOTE: Color(1.0, 0.5, 0.25),
}
const CHAT_COMMANDS: Dictionary[String, WowSession.ChatType] = {
	"/s": WowSession.CHAT_SAY,
	"/say": WowSession.CHAT_SAY,
	"/y": WowSession.CHAT_YELL,
	"/yell": WowSession.CHAT_YELL,
	"/e": WowSession.CHAT_EMOTE,
	"/em": WowSession.CHAT_EMOTE,
	"/me": WowSession.CHAT_EMOTE,
	"/emote": WowSession.CHAT_EMOTE,
	"/p": WowSession.CHAT_PARTY,
	"/party": WowSession.CHAT_PARTY,
	"/g": WowSession.CHAT_GUILD,
	"/guild": WowSession.CHAT_GUILD,
	"/w": WowSession.CHAT_WHISPER,
	"/whisper": WowSession.CHAT_WHISPER,
	"/t": WowSession.CHAT_WHISPER,
	"/tell": WowSession.CHAT_WHISPER,
}

@onready var _player_frame: UnitFrame = %PlayerFrame
@onready var _target_frame: UnitFrame = %TargetFrame
@onready var _chat_log: RichTextLabel = %ChatLog
@onready var _chat_input: LineEdit = %ChatInput


func _ready() -> void:
	WowClient.session.chat_received.connect(_on_chat_received)
	_chat_input.text_submitted.connect(_on_chat_input_submitted)
	_chat_input.gui_input.connect(_on_chat_input_gui_input)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("chat") and not _chat_input.visible:
		get_viewport().set_input_as_handled()
		_chat_input.show()
		_chat_input.grab_focus()


func show_player(guid: int) -> void:
	_player_frame.show_unit(guid)


func show_target(guid: int) -> void:
	_target_frame.show_unit(guid)


func target() -> int:
	return _target_frame.guid if _target_frame.visible else 0


func add_chat_line(text: String, color: Color = Color.WHITE) -> void:
	_chat_log.push_color(color)
	_chat_log.add_text(text)
	_chat_log.pop()
	_chat_log.newline()


func _close_chat() -> void:
	_chat_input.clear()
	_chat_input.release_focus()
	_chat_input.hide()


func _on_chat_received(line: Dictionary) -> void:
	var type: WowSession.ChatType = line["type"] as WowSession.ChatType
	var fields: Dictionary = {
		"name": line.get("sender_name", ""),
		"channel": line.get("channel", ""),
		"text": line.get("text", ""),
	}
	var format: String = CHAT_FORMATS.get(type, "{name}: {text}")
	add_chat_line(format.format(fields), CHAT_COLORS.get(type, Color.WHITE))


func _on_chat_input_submitted(text: String) -> void:
	_close_chat()
	var message: String = text.strip_edges()
	var type: WowSession.ChatType = WowSession.CHAT_SAY
	var whisper_to: String = ""
	if message.begins_with("/"):
		var parts: PackedStringArray = message.split(" ", true, 1)
		if not CHAT_COMMANDS.has(parts[0].to_lower()):
			add_chat_line("Unknown command: " + parts[0], CHAT_COLORS[WowSession.CHAT_SYSTEM])
			return
		type = CHAT_COMMANDS[parts[0].to_lower()]
		message = parts[1] if parts.size() > 1 else ""
		if type == WowSession.CHAT_WHISPER:
			var words: PackedStringArray = message.split(" ", true, 1)
			whisper_to = words[0]
			message = words[1] if words.size() > 1 else ""
	if not message.is_empty():
		WowClient.session.send_chat(type, message, whisper_to)


func _on_chat_input_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_chat_input.accept_event()
		_close_chat()
