class_name QuestWatchFrame
extends Control

signal watches_changed(quest_ids: Array[int])
signal error_raised(text: String)

const MAX_QUESTWATCH_LINES: int = 30
const MAX_WATCHABLE_QUESTS: int = 5
const MAX_QUEST_WATCH_TIMER: float = 300.0
const LINE_HEIGHT: float = 13.0
const TITLE_GAP: float = 4.0
const PADDING: float = 10.0
const TITLE_DONE: Color = Color(1.0, 0.82, 0.0)
const TITLE_OPEN: Color = Color(0.75, 0.61, 0.0)
const OBJECTIVE_OPEN: Color = Color(0.8, 0.8, 0.8)
const TYPE_ITEM: int = 1

# QUEST_WATCH_LIST: watched quest ids and seconds left, or INF for a watch set by hand.
var _watches: Dictionary[int, float] = {}
# Each quest's objective counts, so progress on one can put it on the list for a while.
var _progress: Dictionary[int, Array] = {}


func _ready() -> void:
	%QuestWatchQuestName.hide()
	for i: int in MAX_QUESTWATCH_LINES:
		_line(i).theme_type_variation = &"GameFontHighlight"
	var session: WowSession = WowClient.session
	session.object_updated.connect(_on_object_updated)
	for received: Signal in [
		session.quest_info_received, session.creature_info_received,
		session.game_object_info_received, session.item_info_received,
	]:
		received.connect(func(_id: int) -> void: refresh())
	refresh()


# AutoQuestWatch_OnUpdate: watches set by progress run out after five minutes.
func _process(delta: float) -> void:
	var expired: bool = false
	for quest: int in _watches.keys():
		if is_inf(_watches[quest]):
			continue
		_watches[quest] -= delta
		if _watches[quest] <= 0.0:
			_watches.erase(quest)
			expired = true
	if expired:
		_changed()


func is_watched(quest: int) -> bool:
	return _watches.has(quest)


# Shift-clicking a quest in the log adds it for good, or takes it off.
func toggle(quest: int) -> void:
	if _watches.has(quest):
		_watches.erase(quest)
		_changed()
		return
	var slot: int = _slot(quest)
	var info: Dictionary = WowClient.session.get_quest_info(quest)
	if slot < 0 or QuestLog.objectives(slot, info).is_empty():
		error_raised.emit(WowStrings.get_text("QUEST_WATCH_NO_OBJECTIVES"))
		return
	if _watches.size() >= MAX_WATCHABLE_QUESTS:
		error_raised.emit(WowStrings.get_text("QUEST_WATCH_TOO_MANY") % MAX_WATCHABLE_QUESTS)
		return
	_watches[quest] = INF
	_changed()


# QuestWatch_Update: each watched quest's title, then its objectives, as wide as the longest line.
func refresh() -> void:
	var session: WowSession = WowClient.session
	var index: int = 0
	var y: float = 0.0
	var width: float = 0.0
	for quest: int in _watches:
		var slot: int = _slot(quest)
		var info: Dictionary = session.get_quest_info(quest)
		if slot < 0 or info.is_empty():
			continue
		var lines: Array[Array] = QuestLog.objectives(slot, info)
		if lines.is_empty() or index + lines.size() + 1 > MAX_QUESTWATCH_LINES:
			continue
		if index > 0:
			y += TITLE_GAP
		var done: bool = lines.all(func(line: Array) -> bool: return line[1])
		width = maxf(width, _set_line(index, info["title"], TITLE_DONE if done else TITLE_OPEN, y))
		index += 1
		y += LINE_HEIGHT
		for line: Array in lines:
			var color: Color = Color.WHITE if line[1] else OBJECTIVE_OPEN
			width = maxf(width, _set_line(index, " - " + line[0], color, y))
			index += 1
			y += LINE_HEIGHT
	for i: int in range(index, MAX_QUESTWATCH_LINES):
		_line(i).hide()
	visible = index > 0
	offset_left = offset_right - (width + PADDING)
	offset_bottom = offset_top + (index + 1) * LINE_HEIGHT


func _set_line(index: int, text: String, color: Color, y: float) -> float:
	var line: Label = _line(index)
	line.text = text
	line.self_modulate = color
	line.position = Vector2(0.0, y)
	line.show()
	return line.get_minimum_size().x


func _changed() -> void:
	var watched: Array[int] = []
	watched.assign(_watches.keys())
	watches_changed.emit(watched)
	refresh()


func _line(index: int) -> Label:
	return get_node("%%QuestWatchLine%d" % (index + 1))


func _slot(quest: int) -> int:
	for slot: int in QuestLog.slots():
		if QuestLog.quest_id(slot) == quest:
			return slot
	return -1


# AutoQuestWatch_Update: progress watches a quest for five minutes; one that left the log goes.
func _on_object_updated(guid: int) -> void:
	var session: WowSession = WowClient.session
	if guid != session.get_player_guid():
		# Bag item stacks move item objectives.
		if visible and session.get_object_type(guid) == TYPE_ITEM:
			refresh()
		return
	var current: Dictionary[int, Array] = {}
	for slot: int in QuestLog.slots():
		var quest: int = QuestLog.quest_id(slot)
		var counts: Array = []
		for objective: int in QuestLog.OBJECTIVES:
			counts.append(QuestLog.counter(slot, objective))
		counts.append(QuestLog.state(slot))
		current[quest] = counts
		var moved: bool = _progress.has(quest) and _progress[quest] != counts
		if moved and not is_inf(_watches.get(quest, 0.0)) \
		and (_watches.has(quest) or _watches.size() < MAX_WATCHABLE_QUESTS):
			_watches[quest] = MAX_QUEST_WATCH_TIMER
	var changed: bool = current != _progress
	for quest: int in _watches.keys():
		if not current.has(quest):
			_watches.erase(quest)
	_progress = current
	if changed:
		_changed()
