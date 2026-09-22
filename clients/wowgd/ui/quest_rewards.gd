class_name QuestRewards
extends RefCounted

const MAX_NUM_ITEMS: int = 10


# QuestFrameItems_Update under a heading; returns each button's item entry, or a spell as -id.
static func update(frame: Control, prefix: String, info: Dictionary, above: Control) -> Array[int]:
	var choices: Array = info.get("choices", [])
	var rewards: Array = info.get("rewards", [])
	var spell: int = info.get("reward_spell", 0)
	var money: int = maxi(info.get("money", 0), 0)
	var reward_title: Label = frame.get_node("%" + prefix + "RewardTitleText")
	var choose_text: Label = frame.get_node("%" + prefix + "ItemChooseText")
	var receive_text: Label = frame.get_node("%" + prefix + "ItemReceiveText")
	var spell_text: Label = frame.get_node("%" + prefix + "SpellLearnText")
	var money_frame: MoneyFrame = frame.get_node("%" + prefix + "MoneyFrame")
	var shown: Array[int] = []
	reward_title.visible = choices.size() + rewards.size() + money > 0 or spell != 0
	below(reward_title, above, 15.0)
	money_frame.visible = money > 0
	choose_text.visible = not choices.is_empty()
	if choose_text.visible:
		below(choose_text, reward_title, 5.0)
		_place_items(frame, prefix, choices, shown, choose_text)
	spell_text.visible = spell != 0
	if spell_text.visible:
		var after_choices: bool = not shown.is_empty()
		spell_text.text = WowStrings.get_text("REWARD_SPELL")
		var spell_anchor: Control = item(frame, prefix, shown.size() - 1) if after_choices \
		else reward_title
		below(spell_text, spell_anchor, 5.0, 3.0 if after_choices else 0.0)
		var button: Control = item(frame, prefix, shown.size())
		_set_item(
			frame, prefix, shown.size(), WowAssets.spells.icon(spell),
			WowAssets.spells.spell_name(spell), 0,
		)
		shown.append(-spell)
		below(button, spell_text, 5.0, -3.0)
	receive_text.visible = not rewards.is_empty() or money > 0
	if receive_text.visible:
		var anchor: Control = reward_title
		if spell != 0:
			anchor = item(frame, prefix, shown.size() - 1)
		elif not choices.is_empty():
			anchor = item(frame, prefix, choices.size() - 1 - (1 if choices.size() % 2 == 0 else 0))
		var key: String = "REWARD_ITEMS_ONLY" if anchor == reward_title else "REWARD_ITEMS"
		receive_text.text = WowStrings.get_text(key)
		below(receive_text, anchor, 5.0, 0.0 if anchor == reward_title else 3.0)
		_place_items(frame, prefix, rewards, shown, receive_text)
		if money > 0:
			money_frame.set_money(money)
			beside(money_frame, receive_text, 15.0)
	for i: int in range(shown.size(), MAX_NUM_ITEMS):
		item(frame, prefix, i).hide()
	return shown


static func item(frame: Control, prefix: String, index: int) -> Control:
	return frame.get_node("%%%sItem%d" % [prefix, index + 1])


# Stacks a node under another the way a TOPLEFT to BOTTOMLEFT anchor with an offset does.
static func below(node: Control, above: Control, gap: float, indent: float = 0.0) -> void:
	node.position = Vector2(above.position.x + indent, above.position.y + height(above) + gap)


static func beside(node: Control, left: Control, gap: float) -> void:
	var width: float = left.get_minimum_size().x if left is Label else left.size.x
	node.position = Vector2(
		left.position.x + width + gap, left.position.y + (height(left) - node.size.y) / 2.0,
	)


static func height(node: Control) -> float:
	return maxf(node.size.y, node.get_minimum_size().y)


# Two to a row, the first under its heading.
static func _place_items(
	frame: Control, prefix: String, items: Array, shown: Array[int], heading: Label,
) -> void:
	for i: int in items.size():
		var reward: Vector2i = items[i]
		var index: int = shown.size()
		var info: Dictionary = WowClient.session.get_item_info(reward.x)
		_set_item(frame, prefix, index, Inventory.icon(reward.x), info.get("name", ""), reward.y)
		shown.append(reward.x)
		var button: Control = item(frame, prefix, index)
		if i == 0:
			below(button, heading, 5.0, -3.0)
		elif i % 2 == 0:
			below(button, item(frame, prefix, index - 2), 2.0)
		else:
			var left: Control = item(frame, prefix, index - 1)
			button.position = left.position + Vector2(left.size.x + 1.0, 0.0)


static func _set_item(
	frame: Control, prefix: String, index: int, icon: Texture2D, item_name: String, count: int,
) -> void:
	var name_prefix: String = "%%%sItem%d" % [prefix, index + 1]
	(frame.get_node(name_prefix + "IconTexture") as TextureRect).texture = icon
	var name_label: Label = frame.get_node(name_prefix + "Name")
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.text = item_name
	var count_label: Label = frame.get_node(name_prefix + "Count")
	count_label.text = str(count)
	count_label.visible = count > 1
	item(frame, prefix, index).show()
