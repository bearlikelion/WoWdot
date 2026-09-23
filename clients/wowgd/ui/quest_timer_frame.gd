class_name QuestTimerFrame
extends Control

signal quest_selected(slot: int)

const MAX_TIMERS: int = 20
# QuestTimerFrame_Update: the frame is this tall plus a line per timer.
const BASE_HEIGHT: float = 45.0
const LINE_HEIGHT: float = 16.0

var _slots: Array[int] = []
var _buttons: Array[WowButton] = []
var _texts: Array[Label] = []


func _ready() -> void:
	for i: int in range(1, MAX_TIMERS + 1):
		var button: WowButton = get_node("%%QuestTimer%d" % i)
		button.pressed.connect(_on_timer_pressed.bind(i - 1))
		button.mouse_entered.connect(_on_timer_entered.bind(i - 1))
		button.mouse_exited.connect(_on_timer_exited.bind(i - 1))
		_buttons.append(button)
		_texts.append(get_node("%%QuestTimer%dText" % i))
	WowClient.session.object_updated.connect(_on_object_updated)
	refresh()


func _process(_delta: float) -> void:
	var now: int = int(Time.get_unix_time_from_system())
	for i: int in _slots.size():
		_texts[i].text = WowStrings.seconds_to_time(maxi(QuestLog.time_left(_slots[i]) - now, 0))


# GetQuestTimers: quests whose timer still runs; 1 marks one that already failed.
func refresh() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	_slots.assign(QuestLog.slots().filter(func(slot: int) -> bool:
		return QuestLog.time_left(slot) > now
	))
	for i: int in MAX_TIMERS:
		_buttons[i].visible = i < _slots.size()
	size.y = BASE_HEIGHT + LINE_HEIGHT * _slots.size()
	visible = not _slots.is_empty()
	set_process(visible)


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid():
		refresh()


# QuestTimerButton_OnClick: opens the quest log on the timed quest.
func _on_timer_pressed(index: int) -> void:
	if index < _slots.size():
		quest_selected.emit(_slots[index])


func _on_timer_entered(index: int) -> void:
	if index < _slots.size() and GameTooltip.current:
		var info: Dictionary = WowClient.session.get_quest_info(QuestLog.quest_id(_slots[index]))
		GameTooltip.current.set_text(_buttons[index], info.get("title", ""))


func _on_timer_exited(index: int) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(_buttons[index])
