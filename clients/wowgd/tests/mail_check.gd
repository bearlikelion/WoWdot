class_name MailCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 15000
# A mailbox in the Ironforge bank, and Coldridge Valley to come home to.
const MAILBOX: Vector3 = Vector3(-4910.4, -976.2, 501.4)
const HOME: Vector3 = Vector3(-6248.77, 317.339, 382.778)
const GAMEOBJECT_TYPE_MAILBOX: int = 19
const QUERY_SECONDS: float = 3.0
const SUBJECT: String = "Checkmail"
const BODY: String = "A letter from the check."

var _failures: PackedStringArray = []
var _main: Main


# Sends the player a letter, opens the mailbox, reads it and deletes it.
func _ready() -> void:
	_main = MAIN.instantiate()
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
	var hud: Hud = _main.world.hud()
	var inbox: MailFrame = hud.find_child("MailFrame", true, false)
	var letter: OpenMailFrame = hud.find_child("OpenMailFrame", true, false)
	var me: String = session.get_object_name(session.get_player_guid())
	session.send_chat(WowSession.CHAT_SAY, '.send mail %s "%s" "%s"' % [me, SUBJECT, BODY])
	await _teleport(MAILBOX)
	var mailbox: int = await _nearest_mailbox()
	if mailbox == 0:
		await _teleport(HOME)
		return _finish("no mailbox in the Ironforge bank")
	hud.open_mailbox(mailbox)
	var opened: bool = await _until(func() -> bool: return inbox.visible)
	_check(opened, "a mailbox opens the inbox")
	if not opened:
		await _teleport(HOME)
		return _finish("the inbox never opened")
	var listed: bool = await _until(func() -> bool: return _subject_shown(inbox))
	_check(listed, "the letter is listed")
	if listed:
		(inbox.get_node("%MailItem1Button") as BaseButton).pressed.emit()
		await _frames(10)
		_check(letter.visible, "clicking a letter opens it")
		_check((letter.get_node("%OpenMailSubject") as Label).text == SUBJECT,
			"the letter shows its subject")
		(letter.get_node("%OpenMailDeleteButton") as BaseButton).pressed.emit()
		var gone: bool = await _until(func() -> bool: return not letter.visible)
		_check(gone, "deleting closes the letter")
	(inbox.get_node("%InboxCloseButton") as BaseButton).pressed.emit()
	await _frames(10)
	_check(not inbox.visible, "the close button shuts the inbox")
	await _teleport(HOME)
	_finish("")


func _subject_shown(inbox: MailFrame) -> bool:
	for i: int in MailFrame.MAILS_PER_PAGE:
		var label: Label = inbox.get_node("%%MailItem%dSubject" % (i + 1))
		if label.text == SUBJECT:
			return true
	return false


# Game object names and types arrive from queries, which headless frames outrun.
func _nearest_mailbox() -> int:
	var session: WowSession = WowClient.session
	var objects: Array[int] = []
	for guid: int in session.get_object_guids():
		if session.get_object_type(guid) == Entities.ObjectType.GAMEOBJECT:
			objects.append(guid)
			session.get_game_object_info(session.get_field(guid, "OBJECT_FIELD_ENTRY"))
	await get_tree().create_timer(QUERY_SECONDS).timeout
	for guid: int in objects:
		var entry: int = session.get_field(guid, "OBJECT_FIELD_ENTRY")
		if session.get_game_object_info(entry).get("type", 0) == GAMEOBJECT_TYPE_MAILBOX:
			return guid
	return 0


func _teleport(wow_position: Vector3) -> void:
	WowClient.session.send_chat(
		WowSession.CHAT_SAY, ".go xyz %f %f %f" % [wow_position.x, wow_position.y, wow_position.z]
	)
	await get_tree().create_timer(1.0).timeout
	var loaded_by: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while not _main.world.player().active and Time.get_ticks_msec() < loaded_by:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout


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
	print("mail_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
