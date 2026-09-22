class_name QuestFrame
extends Control

signal close_requested
signal open_requested
signal error_raised(text: String)

enum Page { GREETING, DETAIL, PROGRESS, REWARD }

const SHARE_ACCEPTED: int = 2
const SHARE_DECLINED: int = 3
const MAX_NUM_QUESTS: int = 32
const MAX_REQUIRED_ITEMS: int = 6
const QUEST_DESCRIPTION_GRADIENT_CPS: float = 40.0
const QUESTINFO_FADE_IN: float = 1.0
const PANELS: Dictionary[Page, String] = {
	Page.GREETING: "QuestFrameGreetingPanel",
	Page.DETAIL: "QuestFrameDetailPanel",
	Page.PROGRESS: "QuestFrameProgressPanel",
	Page.REWARD: "QuestFrameRewardPanel",
}
const MATERIAL_PIECES: PackedStringArray = ["TopLeft", "TopRight", "BotLeft", "BotRight"]
const NOT_ENOUGH_MONEY: Color = Color(1.0, 0.1, 0.1)
# Where the reward highlight sits against the chosen item.
const HIGHLIGHT_OFFSET: Vector2 = Vector2(-8.0, -7.0)
const PORTRAIT: PackedScene = preload("res://ui/unit_portrait.tscn")
const PORTRAIT_MASK: Shader = preload("res://ui/portrait.gdshader")

var _guid: int = 0
var _quest_id: int = 0
var _greeting_quests: Array[Dictionary] = []
var _progress_items: Array[Vector2i] = []
var _reward_items: Array[int] = []
var _choices: int = 0
var _choice: int = -1
# Characters of the description shown so far while it writes itself out, or -1 once done.
var _written: float = -1.0
var _portrait: UnitPortrait

@onready var _description: Label = %QuestDescription
@onready var _alpha_frame: Control = %TextAlphaDependentFrame
@onready var _accept: BaseButton = %QuestFrameAcceptButton


func _ready() -> void:
	for panel: String in PANELS.values():
		for piece: String in MATERIAL_PIECES:
			(get_node("%" + panel + "Material" + piece) as CanvasItem).hide()
	for label_name: String in [
		"GreetingText", "QuestDescription", "QuestObjectiveText", "QuestProgressText",
		"QuestRewardText", "QuestTitleText", "QuestProgressTitleText", "QuestRewardTitleText",
	]:
		(get_node("%" + label_name) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i: int in MAX_NUM_QUESTS:
		var button: BaseButton = get_node("%%QuestTitleButton%d" % (i + 1))
		button.pressed.connect(_on_title_pressed.bind(i))
		(get_node("%%QuestTitleButton%dText" % (i + 1)) as Label).autowrap_mode = \
		TextServer.AUTOWRAP_WORD_SMART
	for i: int in QuestRewards.MAX_NUM_ITEMS:
		for prefix: String in ["QuestDetail", "QuestReward"]:
			var item: BaseButton = QuestRewards.item(self, prefix, i)
			item.mouse_entered.connect(_on_reward_entered.bind(item, i))
			item.mouse_exited.connect(_hide_tooltip.bind(item))
		(QuestRewards.item(self, "QuestReward", i) as BaseButton).pressed.connect(_choose.bind(i))
	for i: int in MAX_REQUIRED_ITEMS:
		var item: BaseButton = get_node("%%QuestProgressItem%d" % (i + 1))
		item.mouse_entered.connect(_on_required_entered.bind(item, i))
		item.mouse_exited.connect(_hide_tooltip.bind(item))
	%QuestRewardItemHighlight.hide()
	%QuestSpacerFrame.hide()
	# The name frame sits above the panel art, which the scene order would draw over it.
	move_child(%QuestNpcNameFrame, get_child_count() - 1)
	_accept.pressed.connect(_on_accept_pressed)
	%QuestFrameCompleteButton.pressed.connect(_send.bind("CMSG_QUESTGIVER_REQUEST_REWARD"))
	%QuestFrameCompleteQuestButton.pressed.connect(_on_complete_pressed)
	for decline: BaseButton in [
		%QuestFrameDeclineButton, %QuestFrameGoodbyeButton, %QuestFrameCancelButton,
		%QuestFrameGreetingGoodbyeButton,
	]:
		decline.pressed.connect(_decline)
	%QuestFrameCloseButton.pressed.connect(close_requested.emit)
	_portrait = PORTRAIT.instantiate()
	add_child(_portrait)
	var mask: ShaderMaterial = ShaderMaterial.new()
	mask.shader = PORTRAIT_MASK
	%QuestFramePortrait.material = mask
	%QuestFramePortrait.texture = _portrait.get_texture()
	var session: WowSession = WowClient.session
	session.quest_greeting_received.connect(_on_greeting_received)
	session.quest_details_received.connect(_on_details_received)
	session.quest_progress_received.connect(_on_progress_received)
	session.quest_reward_received.connect(_on_reward_received)
	session.quest_completed.connect(_on_quest_completed)
	session.gossip_closed.connect(close_requested.emit)
	session.item_info_received.connect(_on_item_info_received)


# QuestFrameDetailPanel_OnUpdate: the description writes itself out, then the rest fades in.
func _process(delta: float) -> void:
	if _written < 0.0:
		return
	_written += delta * QUEST_DESCRIPTION_GRADIENT_CPS
	if WowAssets.interface.is_on(&"instant_quest_text"):
		_written = INF
	_description.visible_characters = int(_written)
	if _written >= _description.get_total_character_count():
		_written = -1.0
		_description.visible_characters = -1
		create_tween().tween_property(_alpha_frame, "modulate:a", 1.0, QUESTINFO_FADE_IN)
		_accept.disabled = false


# QuestFrameGreetingPanel_OnShow: quests in progress, a break, then the ones on offer.
func _on_greeting_received(greeting: Dictionary) -> void:
	_open(greeting, Page.GREETING)
	var text: Label = %GreetingText
	text.text = QuestLog.format_text(greeting["text"])
	var active: Array[Dictionary] = []
	var available: Array[Dictionary] = []
	for quest: Dictionary in greeting["quests"]:
		if quest["icon"] == NpcDialog.Status.AVAILABLE:
			available.append(quest)
		else:
			active.append(quest)
	_greeting_quests.assign(active + available)
	var current: Label = %CurrentQuestsText
	var available_text: Label = %AvailableQuestsText
	var line: CanvasItem = %QuestGreetingFrameHorizontalBreak
	current.visible = not active.is_empty()
	available_text.visible = not available.is_empty()
	line.visible = current.visible and available_text.visible
	var above: Control = text
	if current.visible:
		QuestRewards.below(current, text, 10.0)
		above = _stack_titles(0, active, current)
	if available_text.visible:
		if current.visible:
			QuestRewards.below(line, above, 10.0, 22.0)
			QuestRewards.below(available_text, line, 10.0, -12.0)
		else:
			QuestRewards.below(available_text, text, 10.0)
		_stack_titles(active.size(), available, available_text)
	for i: int in range(_greeting_quests.size(), MAX_NUM_QUESTS):
		(get_node("%%QuestTitleButton%d" % (i + 1)) as CanvasItem).hide()
	(%QuestGreetingScrollFrame as WowScrollFrame).refresh()


# QuestFrameDetailPanel_OnShow.
func _on_details_received(details: Dictionary) -> void:
	_open(details, Page.DETAIL)
	var title: Label = %QuestTitleText
	title.text = details["title"]
	_description.text = QuestLog.format_text(details["text"])
	QuestRewards.below(_description, title, 5.0)
	_alpha_frame.position = Vector2.ZERO
	var objective_title: Label = %QuestDetailObjectiveTitleText
	var objectives: Label = %QuestObjectiveText
	objectives.text = QuestLog.format_text(details["objectives"])
	QuestRewards.below(objective_title, _description, 15.0)
	QuestRewards.below(objectives, objective_title, 5.0)
	_reward_items = QuestRewards.update(self, "QuestDetail", details, objectives)
	_fit_alpha_frame()
	(%QuestDetailScrollFrame as WowScrollFrame).refresh()
	_alpha_frame.modulate.a = 0.0
	_accept.disabled = true
	_description.visible_characters = 0
	_written = 0.0


# QuestFrameProgressPanel_OnShow and QuestFrameProgressItems_Update.
func _on_progress_received(progress: Dictionary) -> void:
	_open(progress, Page.PROGRESS)
	var title: Label = %QuestProgressTitleText
	var text: Label = %QuestProgressText
	title.text = progress["title"]
	text.text = QuestLog.format_text(progress["text"])
	QuestRewards.below(text, title, 5.0)
	(%QuestFrameCompleteButton as BaseButton).disabled = not progress["completable"]
	_progress_items.assign(progress["items"])
	var money: int = progress["money"]
	var items_text: Label = %QuestProgressRequiredItemsText
	var money_text: Label = %QuestProgressRequiredMoneyText
	var money_frame: MoneyFrame = %QuestProgressRequiredMoneyFrame
	items_text.visible = not _progress_items.is_empty() or money > 0
	money_text.visible = money > 0
	money_frame.visible = money > 0
	QuestRewards.below(items_text, text, 10.0)
	var first_item: Control = %QuestProgressItem1
	if money > 0:
		money_frame.set_money(money)
		money_frame.modulate = NOT_ENOUGH_MONEY if money > Inventory.money() else Color.WHITE
		QuestRewards.below(money_text, items_text, 10.0)
		QuestRewards.beside(money_frame, money_text, 10.0)
		QuestRewards.below(first_item, money_text, 10.0)
	else:
		QuestRewards.below(first_item, items_text, 5.0, -3.0)
	for i: int in MAX_REQUIRED_ITEMS:
		var item: Control = get_node("%%QuestProgressItem%d" % (i + 1))
		item.visible = i < _progress_items.size()
		if not item.visible:
			continue
		var required: Vector2i = _progress_items[i]
		var prefix: String = "%%QuestProgressItem%d" % (i + 1)
		(get_node(prefix + "IconTexture") as TextureRect).texture = Inventory.icon(required.x)
		(get_node(prefix + "Name") as Label).text = \
		WowClient.session.get_item_info(required.x).get("name", "")
		var count: Label = get_node(prefix + "Count")
		count.text = str(required.y)
		count.visible = required.y > 1
		if i > 0 and i % 2 == 0:
			QuestRewards.below(item, get_node("%%QuestProgressItem%d" % (i - 1)), 3.0)
		elif i % 2 == 1:
			var left: Control = get_node("%%QuestProgressItem%d" % i)
			item.position = left.position + Vector2(left.size.x + 2.0, 0.0)
	(%QuestProgressScrollFrame as WowScrollFrame).refresh()


# QuestFrameRewardPanel_OnShow: a choice has to be picked before the quest completes.
func _on_reward_received(reward: Dictionary) -> void:
	_open(reward, Page.REWARD)
	var title: Label = %QuestRewardTitleText
	var text: Label = %QuestRewardText
	title.text = reward["title"]
	text.text = QuestLog.format_text(reward["text"])
	QuestRewards.below(text, title, 5.0)
	_reward_items = QuestRewards.update(self, "QuestReward", reward, text)
	_choices = (reward["choices"] as Array).size()
	_choice = -1
	%QuestRewardItemHighlight.hide()
	(%QuestRewardScrollFrame as WowScrollFrame).refresh()


func _open(dialog: Dictionary, shown: Page) -> void:
	_guid = dialog["guid"]
	_quest_id = dialog.get("quest_id", 0)
	_written = -1.0
	for panel: Page in PANELS:
		(get_node("%" + PANELS[panel]) as CanvasItem).visible = panel == shown
	%QuestFrameNpcNameText.text = WowClient.session.get_object_name(_guid)
	_portrait.show_unit(_guid)
	open_requested.emit()


func _stack_titles(first: int, quests: Array[Dictionary], heading: Control) -> Control:
	var above: Control = heading
	for i: int in quests.size():
		var index: int = first + i
		var button: Control = get_node("%%QuestTitleButton%d" % (index + 1))
		var text: Label = get_node("%%QuestTitleButton%dText" % (index + 1))
		text.text = quests[i]["title"]
		button.size.y = QuestRewards.height(text) + 2.0
		if i == 0:
			QuestRewards.below(button, heading, 5.0, -10.0)
		else:
			QuestRewards.below(button, above, 0.0)
		button.show()
		above = button
	return above


# The objectives and rewards hang off the description, so their frame grows to cover them.
func _fit_alpha_frame() -> void:
	var bottom: float = 0.0
	for child: Node in _alpha_frame.get_children():
		var control: Control = child as Control
		if control and control.visible:
			bottom = maxf(bottom, control.position.y + QuestRewards.height(control))
	_alpha_frame.size = Vector2(_alpha_frame.get_parent_control().size.x, bottom)


func _on_accept_pressed() -> void:
	_answer_share(SHARE_ACCEPTED)
	_send("CMSG_QUESTGIVER_ACCEPT_QUEST")


func _send(opcode: String) -> void:
	NpcDialog.send(opcode, _guid, [_quest_id])


# QuestTitleButton_OnClick: quests in progress ask to complete, the rest ask for their details.
func _on_title_pressed(index: int) -> void:
	var quest: Dictionary = _greeting_quests[index]
	var available: bool = quest["icon"] == NpcDialog.Status.AVAILABLE
	var opcode: String = "CMSG_QUESTGIVER_QUERY_QUEST" if available \
	else "CMSG_QUESTGIVER_COMPLETE_QUEST"
	NpcDialog.send(opcode, _guid, [quest["id"]])


# QuestRewardItem_OnClick: only choices can be picked.
func _choose(index: int) -> void:
	if index >= _choices:
		return
	_choice = index
	var highlight: Control = %QuestRewardItemHighlight
	highlight.position = QuestRewards.item(self, "QuestReward", index).position + HIGHLIGHT_OFFSET
	highlight.show()


# QuestRewardCompleteButton_OnClick.
func _on_complete_pressed() -> void:
	if _choices > 0 and _choice < 0:
		error_raised.emit(WowStrings.get_text("ERR_QUEST_MUST_CHOOSE"))
		return
	NpcDialog.send("CMSG_QUESTGIVER_CHOOSE_REWARD", _guid, [_quest_id, maxi(_choice, 0)])


func _decline() -> void:
	_answer_share(SHARE_DECLINED)
	WowClient.session.send_packet("CMSG_QUESTGIVER_CANCEL", PackedByteArray())
	close_requested.emit()


# A quest offered by another player is a share, and its sharer waits to hear the answer.
func _answer_share(message: int) -> void:
	if not WowClient.session.get_object_type(_guid) == Entities.ObjectType.PLAYER:
		return
	var payload: PackedByteArray = []
	payload.resize(9)
	payload.encode_u64(0, _guid)
	payload.encode_u8(8, message)
	WowClient.session.send_packet("MSG_QUEST_PUSH_RESULT", payload)


func _on_reward_entered(item: BaseButton, index: int) -> void:
	if GameTooltip.current == null or index >= _reward_items.size():
		return
	var reward: int = _reward_items[index]
	if reward < 0:
		GameTooltip.current.set_spell(item, -reward, GameTooltip.TooltipAnchor.RIGHT)
	else:
		GameTooltip.current.set_item(item, reward)


func _on_required_entered(item: BaseButton, index: int) -> void:
	if GameTooltip.current and index < _progress_items.size():
		GameTooltip.current.set_item(item, _progress_items[index].x)


func _on_quest_completed(_quest: int, _xp: int, _money: int) -> void:
	close_requested.emit()


func _hide_tooltip(tooltip_owner: Control) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(tooltip_owner)


# Item names and icons fill in as their queries answer.
func _on_item_info_received(_entry: int) -> void:
	if not visible:
		return
	for i: int in _reward_items.size():
		var reward: int = _reward_items[i]
		for prefix: String in ["QuestDetail", "QuestReward"]:
			var name_prefix: String = "%%%sItem%d" % [prefix, i + 1]
			if reward > 0 and (get_node(name_prefix + "Name") as Label).text.is_empty():
				var info: Dictionary = WowClient.session.get_item_info(reward)
				(get_node(name_prefix + "Name") as Label).text = info.get("name", "")
				var icon: TextureRect = get_node(name_prefix + "IconTexture")
				icon.texture = Inventory.icon(reward)
