class_name QuestRewards
extends RefCounted

const MAX_NUM_ITEMS: int = 10
# QuestInfo.lua templates: block, x offset and gap below the previous shown block.
const TEMPLATE_DETAIL1: Array[Array] = [
	["QuestInfoTitleHeader", 5.0, 10.0],
	["QuestInfoDescriptionText", 0.0, 5.0],
	["QuestInfoFadingFrame", 0.0, 5.0],
]
const TEMPLATE_DETAIL2: Array[Array] = [
	["QuestInfoObjectivesHeader", 0.0, 10.0],
	["QuestInfoObjectivesText", 0.0, 5.0],
	["QuestInfoRewardsFrame", 0.0, 15.0],
	["QuestInfoSpacerFrame", 0.0, 15.0],
]
const TEMPLATE_LOG: Array[Array] = [
	["QuestInfoTitleHeader", 5.0, 5.0],
	["QuestInfoObjectivesText", 0.0, 5.0],
	["QuestInfoTimerFrame", 0.0, 10.0],
	["QuestInfoObjectivesFrame", 0.0, 10.0],
	["QuestInfoRequiredMoneyFrame", 0.0, 0.0],
	["QuestInfoDescriptionHeader", 0.0, 10.0],
	["QuestInfoDescriptionText", 0.0, 5.0],
	["QuestInfoRewardsFrame", 0.0, 10.0],
	["QuestInfoSpacerFrame", 0.0, 10.0],
]
const TEMPLATE_REWARD: Array[Array] = [
	["QuestInfoTitleHeader", 5.0, 10.0],
	["QuestInfoRewardText", 0.0, 5.0],
	["QuestInfoRewardsFrame", 0.0, 10.0],
	["QuestInfoSpacerFrame", 0.0, 10.0],
]
const BLOCKS: PackedStringArray = [
	"QuestInfoTitleHeader", "QuestInfoDescriptionText", "QuestInfoFadingFrame",
	"QuestInfoObjectivesHeader", "QuestInfoObjectivesText", "QuestInfoGroupSize",
	"QuestInfoRewardsFrame", "QuestInfoSpacerFrame", "QuestInfoTimerFrame",
	"QuestInfoObjectivesFrame", "QuestInfoRequiredMoneyFrame", "QuestInfoDescriptionHeader",
	"QuestInfoRewardText",
]


# Blocks the templates list show before their content decides otherwise; the rest hide.
static func show_blocks(frame: Control, templates: Array[Array]) -> void:
	var listed: PackedStringArray = []
	for template: Array in templates:
		for element: Array in template:
			listed.append(element[0])
	for block: String in BLOCKS:
		(frame.get_node("%" + block) as CanvasItem).visible = block in listed


# QuestInfo_Display: shown blocks move under parent and stack top to bottom, which sizes it.
static func stack(frame: Control, parent: Control, template: Array) -> void:
	var last: Control = null
	for element: Array in template:
		var block: Control = frame.get_node("%" + element[0])
		if block.get_parent() != parent:
			block.reparent(parent, false)
		if not block.visible:
			continue
		var offset: Vector2 = Vector2(element[1], element[2])
		block.position = offset if last == null \
		else last.position + Vector2(0.0, height(last)) + offset
		last = block
	parent.size.y = last.position.y + height(last) if last else 0.0


# QuestFrameItems_Update; returns each button's item entry, or a spell as -id.
static func update(frame: Control, info: Dictionary) -> Array[int]:
	var choices: Array = info.get("choices", [])
	var rewards: Array = info.get("rewards", [])
	var spell: int = info.get("reward_spell", 0)
	var money: int = maxi(info.get("money", 0), 0)
	var reward_title: Label = frame.get_node("%QuestInfoRewardsHeader")
	var choose_text: Label = frame.get_node("%QuestInfoItemChooseText")
	var receive_text: Label = frame.get_node("%QuestInfoItemReceiveText")
	var spell_text: Label = frame.get_node("%QuestInfoSpellLearnText")
	var money_frame: MoneyFrame = frame.get_node("%QuestInfoMoneyFrame")
	var block: Control = frame.get_node("%QuestInfoRewardsFrame")
	var shown: Array[int] = []
	block.visible = choices.size() + rewards.size() + money > 0 or spell != 0
	reward_title.position = Vector2.ZERO
	var last: Control = reward_title
	money_frame.visible = money > 0
	choose_text.visible = not choices.is_empty()
	if choose_text.visible:
		below(choose_text, reward_title, 5.0)
		last = _place_items(frame, choices, shown, choose_text)
	spell_text.visible = spell != 0
	if spell_text.visible:
		spell_text.text = WowStrings.get_text("REWARD_SPELL")
		below(spell_text, last, 5.0, 0.0 if last == reward_title else 3.0)
		var button: Control = item(frame, shown.size())
		_set_item(
			frame, shown.size(), WowAssets.spells.icon(spell),
			WowAssets.spells.spell_name(spell), 0,
		)
		shown.append(-spell)
		below(button, spell_text, 5.0, -3.0)
		last = button
	receive_text.visible = not rewards.is_empty() or money > 0
	if receive_text.visible:
		var key: String = "REWARD_ITEMS_ONLY" if last == reward_title else "REWARD_ITEMS"
		receive_text.text = WowStrings.get_text(key)
		below(receive_text, last, 5.0, 0.0 if last == reward_title else 3.0)
		last = _place_items(frame, rewards, shown, receive_text)
		if money > 0:
			money_frame.set_money(money)
			beside(money_frame, receive_text, 15.0)
	for i: int in range(shown.size(), MAX_NUM_ITEMS):
		item(frame, i).hide()
	block.size.y = last.position.y + height(last)
	return shown


static func item(frame: Control, index: int) -> Control:
	return frame.get_node("%%QuestInfoItem%d" % (index + 1))


# Stacks a node under another the way a TOPLEFT to BOTTOMLEFT anchor with an offset does.
static func below(node: Control, above: Control, gap: float, indent: float = 0.0) -> void:
	node.position = Vector2(above.position.x + indent, above.position.y + height(above) + gap)


static func beside(node: Control, left: Control, gap: float) -> void:
	var width: float = left.get_minimum_size().x if left is Label else left.size.x
	node.position = Vector2(
		left.position.x + width + gap, left.position.y + (height(left) - node.size.y) / 2.0,
	)


# A label keeps the size a longer text grew it to, so only its minimum is trusted.
static func height(node: Control) -> float:
	return node.get_minimum_size().y if node is Label else node.size.y


# Two to a row, the first under its heading; returns the last row's first button.
static func _place_items(
	frame: Control, items: Array, shown: Array[int], heading: Label,
) -> Control:
	var last: Control = heading
	for i: int in items.size():
		var reward: Vector2i = items[i]
		var index: int = shown.size()
		var info: Dictionary = WowClient.session.get_item_info(reward.x)
		_set_item(frame, index, Inventory.icon(reward.x), info.get("name", ""), reward.y)
		shown.append(reward.x)
		var button: Control = item(frame, index)
		if i == 0:
			below(button, heading, 5.0, -3.0)
			last = button
		elif i % 2 == 0:
			below(button, item(frame, index - 2), 2.0)
			last = button
		else:
			var left: Control = item(frame, index - 1)
			button.position = left.position + Vector2(left.size.x + 1.0, 0.0)
	return last


static func _set_item(
	frame: Control, index: int, icon: Texture2D, item_name: String, count: int,
) -> void:
	var name_prefix: String = "%%QuestInfoItem%d" % (index + 1)
	(frame.get_node(name_prefix + "IconTexture") as TextureRect).texture = icon
	var name_label: Label = frame.get_node(name_prefix + "Name")
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.text = item_name
	var count_label: Label = frame.get_node(name_prefix + "Count")
	count_label.text = str(count)
	count_label.visible = count > 1
	item(frame, index).show()
