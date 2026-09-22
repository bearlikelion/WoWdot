class_name GossipFrame
extends Control

signal close_requested
signal open_requested

enum Row { AVAILABLE, ACTIVE, OPTION, SPACER }

const NUMGOSSIPBUTTONS: int = 32
const ICON_PATH: String = "Interface\\GossipFrame\\%sGossipIcon.blp"
# GossipOptionIcon order; later icons draw as plain gossip.
const OPTION_ICONS: PackedStringArray = [
	"Gossip", "Vendor", "Taxi", "Trainer", "Healer", "Binder", "Banker", "Petition", "Tabard",
	"BattleMaster",
]
# The first row hangs 10 left of and 20 below the greeting text.
const FIRST_ROW_OFFSET: Vector2 = Vector2(-10.0, 20.0)
const AVAILABLE_QUEST_ICON: String = "Interface\\GossipFrame\\AvailableQuestIcon.blp"
const ACTIVE_QUEST_ICON: String = "Interface\\GossipFrame\\ActiveQuestIcon.blp"
const PORTRAIT: PackedScene = preload("res://ui/unit_portrait.tscn")
const PORTRAIT_MASK: Shader = preload("res://ui/portrait.gdshader")

var _gossip: Dictionary = {}
var _rows: Array[Dictionary] = []
var _icons: Dictionary[String, WowTexture] = {}
var _portrait: UnitPortrait

@onready var _greeting: Label = %GossipGreetingText
@onready var _scroll: WowScrollFrame = %GossipGreetingScrollFrame


func _ready() -> void:
	_greeting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i: int in NUMGOSSIPBUTTONS:
		_button(i).pressed.connect(_on_button_pressed.bind(i))
		_text(i).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%GossipFrameGreetingGoodbyeButton.pressed.connect(close_requested.emit)
	%GossipFrameCloseButton.pressed.connect(close_requested.emit)
	%GossipSpacerFrame.hide()
	# The name frame sits above the panel art, which the scene order would draw over it.
	move_child(%GossipNpcNameFrame, get_child_count() - 1)
	_portrait = PORTRAIT.instantiate()
	add_child(_portrait)
	var mask: ShaderMaterial = ShaderMaterial.new()
	mask.shader = PORTRAIT_MASK
	%GossipFramePortrait.material = mask
	%GossipFramePortrait.texture = _portrait.get_texture()
	var session: WowSession = WowClient.session
	session.gossip_received.connect(_on_gossip_received)
	session.gossip_closed.connect(close_requested.emit)
	session.npc_text_received.connect(_on_npc_text_received)


# GossipFrameUpdate: available quests, then active quests, then options, a blank row between groups.
func _on_gossip_received(gossip: Dictionary) -> void:
	_gossip = gossip
	_rows.clear()
	var available: Array[Dictionary] = []
	var active: Array[Dictionary] = []
	for quest: Dictionary in gossip["quests"]:
		var row: Dictionary = {"id": quest["id"], "text": quest["title"]}
		if quest["icon"] == NpcDialog.Status.AVAILABLE:
			row["kind"] = Row.AVAILABLE
			available.append(row)
		else:
			row["kind"] = Row.ACTIVE
			active.append(row)
	_rows.append_array(available)
	if not available.is_empty():
		_rows.append({"kind": Row.SPACER})
	_rows.append_array(active)
	if not active.is_empty():
		_rows.append({"kind": Row.SPACER})
	for option: Dictionary in gossip["options"]:
		_rows.append({
			"kind": Row.OPTION, "id": option["index"], "text": option["text"], "icon": option["icon"],
		})
	var guid: int = gossip["guid"]
	%GossipFrameNpcNameText.text = WowClient.session.get_object_name(guid)
	_portrait.show_unit(guid)
	open_requested.emit()
	_update()


func _update() -> void:
	var options: Array = WowClient.session.get_npc_text(_gossip["text_id"], _gossip["guid"])
	_greeting.text = NpcDialog.npc_text(options)
	var above: Control = _greeting
	for i: int in NUMGOSSIPBUTTONS:
		var button: Control = _button(i)
		button.visible = i < _rows.size() and _rows[i]["kind"] != Row.SPACER
		if i >= _rows.size():
			continue
		var row: Dictionary = _rows[i]
		var text: Label = _text(i)
		text.text = row.get("text", "")
		var icon: TextureRect = get_node("%%GossipTitleButton%dGossipIcon" % (i + 1))
		icon.texture = _icon(row)
		# GossipResize: the row is as tall as its wrapped text.
		button.size.y = QuestRewards.height(text) + 2.0
		if i == 0:
			QuestRewards.below(button, _greeting, FIRST_ROW_OFFSET.y, FIRST_ROW_OFFSET.x)
		else:
			QuestRewards.below(button, above, 0.0)
		above = button
	_scroll.refresh()


func _icon(row: Dictionary) -> Texture2D:
	var path: String = ""
	match row["kind"]:
		Row.AVAILABLE:
			path = AVAILABLE_QUEST_ICON
		Row.ACTIVE:
			path = ACTIVE_QUEST_ICON
		Row.OPTION:
			var icon: int = row["icon"]
			path = ICON_PATH % OPTION_ICONS[icon if icon < OPTION_ICONS.size() else 0]
		_:
			return null
	if not _icons.has(path):
		var texture: WowTexture = WowTexture.new()
		texture.file = path
		_icons[path] = texture
	return _icons[path]


func _button(index: int) -> BaseButton:
	return get_node("%%GossipTitleButton%d" % (index + 1))


func _text(index: int) -> Label:
	return get_node("%%GossipTitleButton%dText" % (index + 1))


# GossipTitleButton_OnClick: quests go to the quest frame, options back to the server's gossip.
func _on_button_pressed(index: int) -> void:
	var row: Dictionary = _rows[index]
	var guid: int = _gossip["guid"]
	match row["kind"]:
		Row.AVAILABLE:
			NpcDialog.send("CMSG_QUESTGIVER_QUERY_QUEST", guid, [row["id"]])
		Row.ACTIVE:
			NpcDialog.send("CMSG_QUESTGIVER_COMPLETE_QUEST", guid, [row["id"]])
		Row.OPTION:
			NpcDialog.send("CMSG_GOSSIP_SELECT_OPTION", guid, [row["id"]])


func _on_npc_text_received(text_id: int) -> void:
	if visible and _gossip.get("text_id", -1) == text_id:
		_update()
