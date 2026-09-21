class_name NpcCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
# Dwarven Outfitters, which Sten Stoutarm in Coldridge Valley hands out.
const QUEST: int = 179
const STAND_OFF: float = 4.0

var _failures: PackedStringArray = []
var _main: Main


# Quest givers show markers; talking to one runs gossip or the quest frame through to accepting.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = "127.0.0.1"
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var give_up: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _main.world == null or not _main.world.player().active:
		if Time.get_ticks_msec() > give_up:
			return _finish("never reached the world")
		await get_tree().process_frame
	await _frames(120)
	var session: WowSession = WowClient.session
	var entities: Entities = _main.world.get_node("Entities")
	var markers: Dictionary = entities.get("_markers")
	print("quest givers with markers: %d" % markers.size())
	for guid: int in markers:
		print("  %s" % session.get_object_name(guid))
	_check(not markers.is_empty(), "quest givers show markers")
	var giver: int = await _giver_offering(entities)
	if giver == 0:
		return _finish("no quest giver nearby offers quest %d" % QUEST)
	var home: Vector3 = session.get_object_position(session.get_player_guid())
	# Four yards in front of the quest giver, turned to face it.
	var facing: float = session.get_object_orientation(giver)
	var spot: Vector3 = session.get_object_position(giver) \
	+ Vector3(cos(facing), sin(facing), 0.0) * STAND_OFF
	session.send_chat(WowSession.CHAT_SAY, ".go xyz %f %f %f" % [spot.x, spot.y, spot.z])
	await _frames(90)
	var player: Player = _main.world.player()
	player.place(player.global_position, facing + PI)
	await _frames(30)
	_capture("user://npc_marker.png")
	var panels: PanelManager = _main.world.hud().get_node("%UIPanels")
	var gossip: GossipFrame = panels.get_node("%GossipFrame")
	var quest_frame: QuestFrame = panels.get_node("%QuestFrame")
	NpcDialog.interact(giver)
	await _frames(60)
	print("talked to %s: gossip %s, quest frame %s" % [
		session.get_object_name(giver), gossip.visible, quest_frame.visible,
	])
	_check(gossip.visible or quest_frame.visible, "talking to a quest giver opens a dialog")
	if gossip.visible:
		_capture("user://npc_gossip.png")
		var rows: Array = gossip.get("_rows")
		for i: int in rows.size():
			if rows[i].get("id", 0) == QUEST and rows[i]["kind"] == GossipFrame.Row.AVAILABLE:
				(gossip.get_node("%%GossipTitleButton%d" % (i + 1)) as BaseButton).pressed.emit()
		await _frames(60)
	elif quest_frame.get_node("%QuestFrameGreetingPanel").visible:
		_capture("user://npc_greeting.png")
		var quests: Array = quest_frame.get("_greeting_quests")
		for i: int in quests.size():
			if quests[i]["id"] == QUEST:
				var button: BaseButton = quest_frame.get_node("%%QuestTitleButton%d" % (i + 1))
				button.pressed.emit()
		await _frames(60)
	var detail: Control = quest_frame.get_node("%QuestFrameDetailPanel")
	_check(quest_frame.visible and detail.visible, "picking the quest shows its details")
	var title: Label = quest_frame.get_node("%QuestTitleText")
	print("details: '%s'" % title.text)
	await _frames(20)
	_capture("user://npc_detail_writing.png")
	var accept: BaseButton = quest_frame.get_node("%QuestFrameAcceptButton")
	give_up = Time.get_ticks_msec() + 20000
	while accept.disabled and Time.get_ticks_msec() < give_up:
		await get_tree().process_frame
	await _frames(70)
	_capture("user://npc_detail.png")
	accept.pressed.emit()
	await _frames(60)
	var slot: int = _slot_of(QUEST)
	_check(slot >= 0, "Accept puts the quest in the log")
	_check(not quest_frame.visible, "accepting closes the quest frame")
	await _frames(60)
	print("marker after accepting: %s" % (markers.has(giver)))
	_capture("user://npc_accepted.png")
	if slot >= 0:
		(panels.get_node("%QuestLogFrame") as QuestLogFrame).abandon(slot)
		await _frames(30)
	session.send_chat(WowSession.CHAT_SAY, ".go xyz %f %f %f" % [home.x, home.y, home.z])
	await _frames(60)
	_finish("")


# A quest giver in view whose marker says it has something to hand out.
func _giver_offering(entities: Entities) -> int:
	var statuses: Dictionary = {}
	var session: WowSession = WowClient.session
	session.quest_giver_status_received.connect(
		func(guid: int, status: int) -> void: statuses[guid] = status
	)
	for guid: int in entities.get("_quest_givers"):
		NpcDialog.send("CMSG_QUESTGIVER_STATUS_QUERY", guid)
	await _frames(60)
	for guid: int in statuses:
		if statuses[guid] == NpcDialog.Status.AVAILABLE \
		and session.get_object_name(guid) == "Sten Stoutarm":
			return guid
	return 0


func _slot_of(quest: int) -> int:
	for slot: int in QuestLog.slots():
		if QuestLog.quest_id(slot) == quest:
			return slot
	return -1


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)


func _finish(fatal: String) -> void:
	if not fatal.is_empty():
		_failures.append(fatal)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("npc_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
