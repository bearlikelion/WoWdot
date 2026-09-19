class_name QuestLogFrame
extends Control

signal close_requested
signal abandon_requested(slot: int, title: String)

const QUESTS_DISPLAYED: int = 6
const QUESTLOG_QUEST_HEIGHT: float = 16.0
const MAX_OBJECTIVES: int = 10
const MAX_NUM_ITEMS: int = 10
const MAX_QUESTLOG_QUESTS: int = 20
const PLUS_BUTTON: String = "Interface\\Buttons\\UI-PlusButton-Up.blp"
const MINUS_BUTTON: String = "Interface\\Buttons\\UI-MinusButton-Up.blp"
const PLUS_HIGHLIGHT: String = "Interface\\Buttons\\UI-PlusButton-Hilight.blp"
# QuestDifficultyColor.
const IMPOSSIBLE: Color = Color(1.0, 0.1, 0.1)
const VERY_DIFFICULT: Color = Color(1.0, 0.5, 0.25)
const DIFFICULT: Color = Color(1.0, 1.0, 0.0)
const STANDARD: Color = Color(0.25, 0.75, 0.25)
const TRIVIAL: Color = Color(0.5, 0.5, 0.5)
const HEADER: Color = Color(0.7, 0.7, 0.7)
const OBJECTIVE_DONE: Color = Color(0.2, 0.2, 0.2)
const OBJECTIVE_OPEN: Color = Color(0.0, 0.0, 0.0)
const NOT_ENOUGH_MONEY: Color = Color(1.0, 0.1, 0.1)
const TRACKING_OFF: Color = Color(1.0, 0.0, 0.0)
const WHEEL_BUTTONS: Array[MouseButton] = [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]

# GetQuestLogTitle rows: zone headers, each followed by its quests unless collapsed.
var _entries: Array[Dictionary] = []
var _collapsed: Dictionary[String, bool] = {}
var _selected_slot: int = -1
var _offset: int = 0
var _quest_types: WowDBC
var _textures: Dictionary[String, WowTexture] = {}
var _reward_items: Array[int] = []

@onready var _list_scroll: WowScrollFrame = %QuestLogListScrollFrame
@onready var _detail_scroll: WowScrollFrame = %QuestLogDetailScrollFrame
@onready var _highlight: Control = %QuestLogHighlightFrame


func _ready() -> void:
	_quest_types = WowDBC.open(WowAssets.archive, "QuestInfo")
	for path: String in [PLUS_BUTTON, MINUS_BUTTON, PLUS_HIGHLIGHT]:
		var texture: WowTexture = WowTexture.new()
		texture.file = path
		_textures[path] = texture
	for i: int in QUESTS_DISPLAYED:
		_title(i).pressed.connect(_on_title_pressed.bind(i))
	%QuestLogCollapseAllButton.pressed.connect(_on_collapse_all_pressed)
	%QuestLogFrameCloseButton.pressed.connect(close_requested.emit)
	%QuestFrameExitButton.pressed.connect(close_requested.emit)
	%QuestLogFrameAbandonButton.pressed.connect(_on_abandon_pressed)
	# Sharing waits on parties and tracking on the quest watch frame.
	%QuestFramePushQuestButton.disabled = true
	%QuestLogTrackTracking.self_modulate = TRACKING_OFF
	%QuestLogSpacerFrame.hide()
	for label_name: String in ["QuestLogObjectivesText", "QuestLogQuestDescription"]:
		(get_node("%" + label_name) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i: int in MAX_OBJECTIVES:
		_objective(i).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i: int in MAX_NUM_ITEMS:
		var item: BaseButton = _item(i)
		(get_node("%%QuestLogItem%dName" % (i + 1)) as Label).autowrap_mode = \
		TextServer.AUTOWRAP_WORD_SMART
		item.mouse_entered.connect(_on_item_entered.bind(i))
		item.mouse_exited.connect(_hide_tooltip.bind(item))
	_list_scroll.scrolled.connect(_on_list_scrolled)
	var session: WowSession = WowClient.session
	session.object_updated.connect(_on_object_updated)
	for received: Signal in [
		session.quest_info_received, session.creature_info_received,
		session.game_object_info_received, session.item_info_received,
	]:
		received.connect(func(_id: int) -> void: refresh(true))
	visibility_changed.connect(refresh)


func _gui_input(event: InputEvent) -> void:
	var wheel: InputEventMouseButton = event as InputEventMouseButton
	var over_list: bool = wheel and _list_rect().has_point(wheel.position)
	if over_list and wheel.pressed and wheel.button_index in WHEEL_BUTTONS:
		accept_event()
		var up: bool = wheel.button_index == MOUSE_BUTTON_WHEEL_UP
		_list_scroll.scroll_to(_list_scroll.scroll() + (-1.0 if up else 1.0) * QUESTLOG_QUEST_HEIGHT)


# QuestLog_Update, then QuestLog_UpdateQuestDetails; keep_scroll leaves the details where they were.
func refresh(keep_scroll: bool = false) -> void:
	if not is_visible_in_tree():
		return
	_build_entries()
	var listed: bool = _entries.any(func(entry: Dictionary) -> bool:
		return not entry["header"] and entry["slot"] == _selected_slot
	)
	if not listed:
		_selected_slot = -1
		for entry: Dictionary in _entries:
			if not entry["header"]:
				_selected_slot = entry["slot"]
				break
	_update_list()
	_update_details(keep_scroll)


func abandon(slot: int) -> void:
	WowClient.session.send_packet("CMSG_QUESTLOG_REMOVE_QUEST", PackedByteArray([slot]))


func _build_entries() -> void:
	var groups: Dictionary[String, Array] = {}
	var session: WowSession = WowClient.session
	for slot: int in QuestLog.slots():
		var info: Dictionary = session.get_quest_info(QuestLog.quest_id(slot))
		if info.is_empty():
			continue
		var header: String = QuestLog.header(info)
		if not groups.has(header):
			groups[header] = []
		groups[header].append(slot)
	_entries.clear()
	for header: String in groups:
		var collapsed: bool = _collapsed.has(header)
		_entries.append({"header": true, "title": header, "collapsed": collapsed, "slot": -1})
		if collapsed:
			continue
		for slot: int in groups[header]:
			var info: Dictionary = session.get_quest_info(QuestLog.quest_id(slot))
			_entries.append({
				"header": false, "title": info["title"], "level": info["level"],
				"tag": _quest_tag(slot, info), "slot": slot,
			})


func _quest_tag(slot: int, info: Dictionary) -> String:
	match QuestLog.state(slot):
		QuestLog.State.FAILED:
			return WowStrings.get_text("FAILED")
		QuestLog.State.COMPLETE:
			return WowStrings.get_text("COMPLETE")
	var row: int = _quest_types.find(info["type"])
	return _quest_types.get_string(row, "Name") if row >= 0 else ""


func _update_list() -> void:
	var has_quests: bool = not _entries.is_empty()
	%EmptyQuestLogFrame.visible = not has_quests
	%QuestLogFrameAbandonButton.disabled = not has_quests
	_detail_scroll.visible = has_quests
	%QuestLogExpandButtonFrame.visible = has_quests
	_update_count()
	var hidden_entries: int = maxi(_entries.size() - QUESTS_DISPLAYED, 0)
	_list_scroll.visible = hidden_entries > 0
	_list_scroll.set_range(hidden_entries * QUESTLOG_QUEST_HEIGHT)
	_offset = mini(_offset, hidden_entries)
	_highlight.hide()
	for i: int in QUESTS_DISPLAYED:
		var button: WowButton = _title(i)
		var index: int = i + _offset
		button.visible = index < _entries.size()
		if button.visible:
			_show_entry(button, _entries[index])
	var headers: Array[Dictionary] = _entries.filter(
		func(entry: Dictionary) -> bool: return entry["header"]
	)
	var all_collapsed: bool = headers.all(func(entry: Dictionary) -> bool: return entry["collapsed"])
	var collapse_all: TextureRect = %QuestLogCollapseAllButton.get_node("NormalTexture")
	collapse_all.texture = _textures[PLUS_BUTTON if all_collapsed else MINUS_BUTTON]


func _show_entry(button: WowButton, entry: Dictionary) -> void:
	var prefix: String = "%" + button.name
	var text: Label = get_node(prefix + "NormalText")
	var tag: Label = get_node(prefix + "Tag")
	var normal: TextureRect = button.get_node("NormalTexture")
	var highlight: TextureRect = button.get_node("HighlightTexture")
	(get_node(prefix + "Check") as CanvasItem).hide()
	(get_node(prefix + "GroupMates") as Label).text = ""
	var color: Color = HEADER
	if entry["header"]:
		text.text = entry["title"]
		normal.texture = _textures[PLUS_BUTTON if entry["collapsed"] else MINUS_BUTTON]
		highlight.texture = _textures[PLUS_HIGHLIGHT]
		tag.text = ""
	else:
		text.text = "  " + entry["title"]
		normal.texture = null
		highlight.texture = null
		tag.text = "(%s)" % entry["tag"] if not entry["tag"].is_empty() else ""
		color = _difficulty_color(entry["level"])
	# SetTextColor over white text, so the tint is the colour itself.
	for label: Label in [text, tag]:
		label.theme_type_variation = &"GameFontHighlight"
		label.self_modulate = color
	var selected: bool = not entry["header"] and entry["slot"] == _selected_slot
	button.highlight_locked = selected
	if selected:
		_highlight.position = button.position
		%QuestLogSkillHighlight.self_modulate = color
		tag.self_modulate = Color.WHITE
		_highlight.show()


func _update_count() -> void:
	var quests: int = QuestLog.slots().size()
	var count: Label = %QuestLogQuestCount
	count.text = WowStrings.strip_colors(WowStrings.get_text("QUEST_LOG_COUNT_TEMPLATE")) \
	% [quests, MAX_QUESTLOG_QUESTS]
	var middle: Control = %QuestLogCountMiddle
	var right_edge: float = middle.position.x + middle.size.x
	middle.size.x = count.get_minimum_size().x
	middle.position.x = right_edge - middle.size.x
	%QuestLogCountLeft.position.x = middle.position.x - %QuestLogCountLeft.size.x


# GetDifficultyColor: by how far the quest's level is above the player's or below the gray level.
func _difficulty_color(level: int) -> Color:
	var session: WowSession = WowClient.session
	var player_level: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_LEVEL")
	var difference: int = level - player_level
	if difference >= 5:
		return IMPOSSIBLE
	if difference >= 3:
		return VERY_DIFFICULT
	if difference >= -2:
		return DIFFICULT
	return STANDARD if level > _gray_level(player_level) else TRIVIAL


func _gray_level(player_level: int) -> int:
	if player_level <= 5:
		return 0
	if player_level < 40:
		return player_level - 5 - player_level / 10
	if player_level < 60:
		return player_level - 1 - player_level / 5
	return player_level - 9


# QuestLog_UpdateQuestDetails and QuestFrameItems_Update, stacked as their anchors chain.
func _update_details(keep_scroll: bool) -> void:
	if _selected_slot < 0:
		_detail_scroll.hide()
		return
	var info: Dictionary = WowClient.session.get_quest_info(QuestLog.quest_id(_selected_slot))
	var title: String = info["title"]
	if QuestLog.state(_selected_slot) == QuestLog.State.FAILED:
		title += " - (%s)" % WowStrings.get_text("FAILED")
	var title_label: Label = %QuestLogQuestTitle
	title_label.text = title
	var objectives_text: Label = %QuestLogObjectivesText
	objectives_text.text = QuestLog.format_text(info["objectives"])
	_below(objectives_text, title_label, 5.0)
	var last: Control = objectives_text
	var timer: Label = %QuestLogTimerText
	var seconds_left: int = QuestLog.time_left(_selected_slot) - int(Time.get_unix_time_from_system())
	timer.visible = QuestLog.time_left(_selected_slot) > 0
	if timer.visible:
		timer.text = "%s %d:%02d" % [
			WowStrings.get_text("TIME_REMAINING"), maxi(seconds_left, 0) / 60, maxi(seconds_left, 0) % 60,
		]
		_below(timer, last, 10.0)
		last = timer
	var lines: Array[Array] = QuestLog.objectives(_selected_slot, info)
	for i: int in MAX_OBJECTIVES:
		var objective: Label = _objective(i)
		objective.visible = i < lines.size()
		if not objective.visible:
			continue
		var finished: bool = lines[i][1]
		objective.text = lines[i][0]
		if finished:
			objective.text += " (%s)" % WowStrings.get_text("COMPLETE")
		objective.add_theme_color_override("font_color", OBJECTIVE_DONE if finished else OBJECTIVE_OPEN)
		_below(objective, last, 10.0 if i == 0 else 2.0)
		last = objective
	var money: int = info["money"]
	var money_text: Label = %QuestLogRequiredMoneyText
	var money_frame: MoneyFrame = %QuestLogRequiredMoneyFrame
	money_text.visible = money < 0
	money_frame.visible = money < 0
	if money < 0:
		var short: bool = -money > Inventory.money()
		money_text.add_theme_color_override("font_color", OBJECTIVE_OPEN if short else OBJECTIVE_DONE)
		money_frame.modulate = NOT_ENOUGH_MONEY if short else Color.WHITE
		money_frame.set_money(-money)
		_below(money_text, last, 4.0 if not lines.is_empty() else 10.0)
		_beside(money_frame, money_text, 10.0)
		last = money_text
	var description_title: Label = %QuestLogDescriptionTitle
	_below(description_title, last, 10.0)
	var description: Label = %QuestLogQuestDescription
	description.text = QuestLog.format_text(info["details"])
	_below(description, description_title, 5.0)
	_update_rewards(info, description)
	_detail_scroll.show()
	_detail_scroll.refresh(keep_scroll)


func _update_rewards(info: Dictionary, description: Label) -> void:
	var choices: Array = info["choices"]
	var rewards: Array = info["rewards"]
	var spell: int = info["reward_spell"]
	var money: int = maxi(info["money"], 0)
	var reward_title: Label = %QuestLogRewardTitleText
	var choose_text: Label = %QuestLogItemChooseText
	var receive_text: Label = %QuestLogItemReceiveText
	var spell_text: Label = %QuestLogSpellLearnText
	var money_frame: MoneyFrame = %QuestLogMoneyFrame
	reward_title.visible = choices.size() + rewards.size() + money > 0 or spell != 0
	_below(reward_title, description, 15.0)
	money_frame.visible = money > 0
	_reward_items.clear()
	var index: int = 0
	choose_text.visible = not choices.is_empty()
	if choose_text.visible:
		_below(choose_text, reward_title, 5.0)
		index = _place_items(choices, index, choose_text)
	spell_text.visible = spell != 0
	if spell_text.visible:
		spell_text.text = WowStrings.get_text("REWARD_SPELL")
		_below(spell_text, _item(index - 1) if index > 0 else reward_title, 5.0)
		var button: BaseButton = _item(index)
		_set_reward(index, WowAssets.spells.icon(spell), WowAssets.spells.spell_name(spell), 0)
		_reward_items.append(-spell)
		_below(button, spell_text, 5.0, -3.0)
		index += 1
	receive_text.visible = not rewards.is_empty() or money > 0
	if receive_text.visible:
		var anchor: Control = reward_title
		receive_text.text = WowStrings.get_text("REWARD_ITEMS_ONLY")
		if spell != 0:
			anchor = _item(index - 1)
		elif not choices.is_empty():
			anchor = _item(choices.size() - 1 - (1 if choices.size() % 2 == 0 else 0))
		if anchor != reward_title:
			receive_text.text = WowStrings.get_text("REWARD_ITEMS")
		_below(receive_text, anchor, 5.0, 3.0 if anchor != reward_title else 0.0)
		index = _place_items(rewards, index, receive_text)
		if money > 0:
			money_frame.set_money(money)
			_beside(money_frame, receive_text, 15.0)
	for i: int in range(index, MAX_NUM_ITEMS):
		_item(i).hide()


# Two to a row, the first under its heading.
func _place_items(items: Array, start: int, heading: Label) -> int:
	for i: int in items.size():
		var reward: Vector2i = items[i]
		var index: int = start + i
		var info: Dictionary = WowClient.session.get_item_info(reward.x)
		_set_reward(index, Inventory.icon(reward.x), info.get("name", ""), reward.y)
		_reward_items.append(reward.x)
		var button: BaseButton = _item(index)
		if i == 0:
			_below(button, heading, 5.0, -3.0)
		elif i % 2 == 0:
			_below(button, _item(index - 2), 2.0)
		else:
			var left: Control = _item(index - 1)
			button.position = left.position + Vector2(left.size.x + 1.0, 0.0)
	return start + items.size()


func _set_reward(index: int, icon: Texture2D, item_name: String, count: int) -> void:
	var prefix: String = "%%QuestLogItem%d" % (index + 1)
	(get_node(prefix + "IconTexture") as TextureRect).texture = icon
	(get_node(prefix + "Name") as Label).text = item_name
	var count_label: Label = get_node(prefix + "Count")
	count_label.text = str(count)
	count_label.visible = count > 1
	_item(index).show()


func _below(node: Control, above: Control, gap: float, indent: float = 0.0) -> void:
	node.position = Vector2(above.position.x + indent, above.position.y + _height(above) + gap)


func _beside(node: Control, left: Control, gap: float) -> void:
	var width: float = left.get_minimum_size().x if left is Label else left.size.x
	node.position = Vector2(
		left.position.x + width + gap, left.position.y + (_height(left) - node.size.y) / 2.0,
	)


func _height(node: Control) -> float:
	return maxf(node.size.y, node.get_minimum_size().y)


func _list_rect() -> Rect2:
	var first: Control = _title(0)
	return Rect2(first.position, Vector2(first.size.x, QUESTLOG_QUEST_HEIGHT * QUESTS_DISPLAYED))


func _title(index: int) -> WowButton:
	return get_node("%%QuestLogTitle%d" % (index + 1))


func _objective(index: int) -> Label:
	return get_node("%%QuestLogObjective%d" % (index + 1))


func _item(index: int) -> BaseButton:
	return get_node("%%QuestLogItem%d" % (index + 1))


# QuestLogTitleButton_OnClick: headers fold, quests become the selection.
func _on_title_pressed(index: int) -> void:
	var entry: Dictionary = _entries[index + _offset]
	if entry["header"]:
		if entry["collapsed"]:
			_collapsed.erase(entry["title"])
		else:
			_collapsed[entry["title"]] = true
		refresh(true)
		return
	_selected_slot = entry["slot"]
	_update_list()
	_update_details(false)


func _on_collapse_all_pressed() -> void:
	var headers: Array[Dictionary] = _entries.filter(
		func(entry: Dictionary) -> bool: return entry["header"]
	)
	var expand: bool = headers.all(func(entry: Dictionary) -> bool: return entry["collapsed"])
	for entry: Dictionary in headers:
		if expand:
			_collapsed.erase(entry["title"])
		else:
			_collapsed[entry["title"]] = true
	_list_scroll.scroll_to(0.0)
	refresh(true)


func _on_abandon_pressed() -> void:
	if _selected_slot >= 0:
		var info: Dictionary = WowClient.session.get_quest_info(QuestLog.quest_id(_selected_slot))
		abandon_requested.emit(_selected_slot, info.get("title", ""))


func _on_list_scrolled(value: float) -> void:
	var offset: int = roundi(value / QUESTLOG_QUEST_HEIGHT)
	if offset != _offset:
		_offset = offset
		_update_list()


func _on_item_entered(index: int) -> void:
	if GameTooltip.current == null or index >= _reward_items.size():
		return
	var reward: int = _reward_items[index]
	if reward < 0:
		GameTooltip.current.set_spell(_item(index), -reward, GameTooltip.TooltipAnchor.RIGHT)
	else:
		GameTooltip.current.set_item(_item(index), reward)


func _hide_tooltip(owner: Control) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(owner)


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid():
		refresh(true)
