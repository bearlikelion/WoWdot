class_name BattlegroundCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 15000
# Elfarran, the Warsong Gulch battlemaster who stands in Stormwind.
const BATTLEMASTER: int = 14981
const STORMWIND: Vector3 = Vector3(-8454.6, 318.9, 121.0)
const HOME: Vector3 = Vector3(-6248.77, 317.339, 382.778)
# Warsong Gulch asks for level 10, which the starting character is well short of.
const QUEUE_LEVEL: int = 20

var _failures: PackedStringArray = []
var _main: Main


# The queue round trip: a battlemaster lists its battleground, takes a place in it and gives it up.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = "127.0.0.1"
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var ready_at: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _main.world == null or not _main.world.player().active:
		if Time.get_ticks_msec() > ready_at:
			return _finish("never reached the world")
		await get_tree().process_frame
	var session: WowSession = WowClient.session
	var battlegrounds: Battlegrounds = Battlegrounds.new(session)
	session.send_chat(WowSession.CHAT_SAY, ".character level %d" % QUEUE_LEVEL)
	await _frames(120)
	await _teleport(STORMWIND)

	var master: int = 0
	for attempt: int in 8:
		master = _object_with_entry(BATTLEMASTER)
		if master != 0:
			break
		await _frames(180)
	_check(master != 0, "the Warsong battlemaster is in Stormwind")
	if master == 0:
		await _teleport(HOME)
		return _finish("no battlemaster to ask")

	# Joining needs interaction range, and the battlemaster does not stand on its spawn point.
	await _teleport(WowCoords.from_godot(
		_main.world.get_node("Entities").unit_node(master).global_position
	))
	battlegrounds.refused.connect(
		func(reason: int) -> void: printerr("SMSG_GROUP_JOINED_BATTLEGROUND: ", reason)
	)
	var listed: Array = []
	battlegrounds.listed.connect(
		func(map_id: int, instances: PackedInt32Array) -> void:
			listed.append([map_id, instances])
	)
	battlegrounds.ask(master)
	var answered: bool = await _until(func() -> bool: return not listed.is_empty())
	_check(answered, "and answers with the battlegrounds it runs")
	if not answered:
		await _teleport(HOME)
		return _finish("no battlefield list came back")
	print("listed map %d, instances %s" % [listed[0][0], listed[0][1]])
	_check(listed[0][0] == Battlegrounds.WARSONG_GULCH, "which is Warsong Gulch by its map id")

	battlegrounds.join(master, Battlegrounds.WARSONG_GULCH)
	var queued: bool = await _until(
		func() -> bool: return battlegrounds.slot_of(Battlegrounds.WARSONG_GULCH) >= 0
	)
	_check(queued, "joining takes a place in the queue")
	if queued:
		var slot: int = battlegrounds.slot_of(Battlegrounds.WARSONG_GULCH)
		var entry: Dictionary = battlegrounds.queue(slot)
		print("queue slot %d: %s" % [slot, entry])
		_check(
			entry["status"] == Battlegrounds.Status.WAIT_QUEUE,
			"which the server reports as waiting",
		)
		_check(entry["time_two"] < TIMEOUT_MSEC, "with a sane time already spent in it")
		battlegrounds.abandon(Battlegrounds.WARSONG_GULCH)
		_check(
			await _until(
				func() -> bool: return battlegrounds.slot_of(Battlegrounds.WARSONG_GULCH) < 0
			),
			"and giving it up clears the slot again",
		)
	_check(session.get_state() == WowSession.STATE_IN_WORLD, "the session survives the round trip")
	await _teleport(HOME)
	_finish("")


func _object_with_entry(entry: int) -> int:
	var session: WowSession = WowClient.session
	for guid: int in session.get_object_guids():
		if session.get_field(guid, "OBJECT_FIELD_ENTRY") == entry:
			return guid
	return 0


func _teleport(wow_position: Vector3) -> void:
	WowClient.session.send_chat(
		WowSession.CHAT_SAY, ".go xyz %f %f %f 0" % [
			wow_position.x, wow_position.y, wow_position.z,
		]
	)
	await _frames(30)
	await _until(func() -> bool: return _main.world.player().active, TIMEOUT_MSEC)
	await _frames(120)


func _until(condition: Callable, timeout_msec: int = STEP_MSEC) -> bool:
	var until: int = Time.get_ticks_msec() + timeout_msec
	while not condition.call() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	return condition.call()


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)


func _finish(fatal: String) -> void:
	if not fatal.is_empty():
		_failures.append(fatal)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("battleground_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
