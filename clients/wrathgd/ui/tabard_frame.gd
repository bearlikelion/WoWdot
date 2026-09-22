@tool
class_name TabardFrame
extends Control

signal open_requested
signal close_requested
signal error_raised(text: String)
signal message_added(text: String)

# The five rows the stock window cycles, in the order MSG_SAVE_GUILD_EMBLEM takes them.
enum Part { EMBLEM, EMBLEM_COLOR, BORDER, BORDER_COLOR, BACKGROUND }
const PART_LABELS: Dictionary[Part, String] = {
	Part.EMBLEM: "EMBLEM_SYMBOL",
	Part.EMBLEM_COLOR: "EMBLEM_SYMBOL_COLOR",
	Part.BORDER: "EMBLEM_BORDER",
	Part.BORDER_COLOR: "EMBLEM_BORDER_COLOR",
	Part.BACKGROUND: "EMBLEM_BACKGROUND",
}
# How many the archive holds of each, counted from Textures\GuildEmblems.
const PART_COUNTS: Dictionary[Part, int] = {
	Part.EMBLEM: 170, Part.EMBLEM_COLOR: 17, Part.BORDER: 10, Part.BORDER_COLOR: 17,
	Part.BACKGROUND: 51,
}
const EMBLEM_PATH: String = "Textures\\GuildEmblems\\Emblem_%02d_%02d_T%s_U.blp"
# GetTabardCreationCost, which the stock client also hard codes.
const COST: int = 100000
# SMSG guild emblem results, as Guild.h numbers them.
enum Result { SUCCESS, INVALID_TABARD_COLORS, NO_GUILD, NOT_GUILD_MASTER, NOT_ENOUGH_MONEY }
const RESULT_ERRORS: Dictionary[Result, String] = {
	Result.INVALID_TABARD_COLORS: "ERR_GUILD_INTERNAL",
	Result.NO_GUILD: "ERR_PETITION_IN_GUILD",
	Result.NOT_GUILD_MASTER: "ERR_GUILD_PERMISSIONS",
	Result.NOT_ENOUGH_MONEY: "ERR_NOT_ENOUGH_MONEY",
}

var _guid: int = 0
var _parts: Dictionary[Part, int] = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for which: Part in PART_LABELS:
		_parts[which] = 0
		var row: int = which + 1
		(get_node("%%TabardFrameCustomization%dText" % row) as Label).text = \
			WowStrings.get_text(PART_LABELS[which])
		var left: BaseButton = get_node("%%TabardFrameCustomization%dLeftButton" % row)
		var right: BaseButton = get_node("%%TabardFrameCustomization%dRightButton" % row)
		left.pressed.connect(_cycle.bind(which, -1))
		right.pressed.connect(_cycle.bind(which, 1))
	%TabardFrameAcceptButton.pressed.connect(_save)
	%TabardFrameCancelButton.pressed.connect(close_requested.emit)
	%TabardFrameCloseButton.pressed.connect(close_requested.emit)
	(%TabardFrameCostMoneyFrame as MoneyFrame).set_money(COST)
	WowClient.session.packet_received.connect(_on_packet_received)
	hide()


# MSG_TABARDVENDOR_ACTIVATE: the vendor answers with its own guid, and the window opens on that.
func activate(guid: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, guid)
	WowClient.session.send_packet("MSG_TABARDVENDOR_ACTIVATE", payload)


func vendor() -> int:
	return _guid


func part(which: Part) -> int:
	return _parts[which]


# ponytail: only the emblem previews; border and background need the 3D tabard to show anything.
func _cycle(which: Part, step: int) -> void:
	_parts[which] = wrapi(_parts[which] + step, 0, PART_COUNTS[which])
	_refresh()


func _refresh() -> void:
	var emblem: int = _parts[Part.EMBLEM]
	var color: int = _parts[Part.EMBLEM_COLOR]
	for corner: String in ["TopLeft", "TopRight", "BottomLeft", "BottomRight"]:
		var texture: WowTexture = WowTexture.new()
		texture.file = EMBLEM_PATH % [emblem, color, "U" if corner.begins_with("Top") else "L"]
		(get_node("%TabardFrameEmblem" + corner) as TextureRect).texture = texture
	var leader: bool = _is_guild_leader()
	%TabardFrameAcceptButton.disabled = not leader
	(%TabardFrameGreetingText as Label).text = WowStrings.get_text(
		"TABARDVENDORGREETING" if leader else "TABARDVENDORNOGUILDGREETING"
	)


func _is_guild_leader() -> bool:
	var session: WowSession = WowClient.session
	var me: int = session.get_player_guid()
	return session.get_field(me, "PLAYER_GUILDID") != 0 \
	and session.get_field(me, "PLAYER_GUILDRANK") == 0


# MSG_SAVE_GUILD_EMBLEM: the vendor, then the five choices the server writes on the guild.
func _save() -> void:
	var payload: PackedByteArray = []
	payload.resize(28)
	payload.encode_u64(0, _guid)
	for which: Part in PART_LABELS:
		payload.encode_s32(8 + which * 4, _parts[which])
	WowClient.session.send_packet("MSG_SAVE_GUILD_EMBLEM", payload)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"MSG_TABARDVENDOR_ACTIVATE":
			_guid = reader.u64()
			(%TabardFrameNameText as Label).text = WowClient.session.get_object_name(_guid)
			_refresh()
			open_requested.emit()
		"MSG_SAVE_GUILD_EMBLEM":
			_on_saved(reader.u32() as Result)


func _on_saved(result: Result) -> void:
	if result == Result.SUCCESS:
		message_added.emit(WowStrings.get_text("TABARDVENDORALREADYSETGREETING"))
		close_requested.emit()
		return
	error_raised.emit(WowStrings.get_text(RESULT_ERRORS.get(result, "ERR_GUILD_INTERNAL")))
