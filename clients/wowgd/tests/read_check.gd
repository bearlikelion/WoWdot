class_name ReadCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 10000
# The Story of Morgan Ladimore, a book of several pages.
const BOOK: int = 2154
const BACKPACK_SLOTS: int = 16

var _failures: PackedStringArray = []
var _main: Main


# A GM-made book opens in the reading window and turns its page.
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
	await _frames(60)
	var session: WowSession = WowClient.session
	var hud: Hud = _main.world.hud()
	if _book_slot() < 0:
		session.send_chat(WowSession.CHAT_SAY, ".additem %d" % BOOK)
	if not await _until(func() -> bool: return _book_slot() >= 0):
		return _finish("the book never reached the backpack")
	session.get_item_info(BOOK)
	await _until(func() -> bool: return not session.get_item_info(BOOK).is_empty())
	hud.use_container_item(0, _book_slot())
	var frame: Control = hud.find_child("ItemTextFrame", true, false)
	_check(await _until(func() -> bool: return frame.visible), "using the book opens it")
	var page: RichTextLabel = frame.get_node("%ItemTextPageText")
	var first: String = page.get_parsed_text()
	_check(not first.is_empty(), "the first page has words")
	print("page 1: ", first.left(60))
	(frame.get_node("%ItemTextNextPageButton") as BaseButton).pressed.emit()
	var turned: bool = await _until(func() -> bool: return page.get_parsed_text() != first)
	_check(turned, "the next page differs")
	_finish("")


func _book_slot() -> int:
	for slot: int in BACKPACK_SLOTS:
		if Inventory.entry(Inventory.container_item(0, slot)) == BOOK:
			return slot
	return -1


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
	print("read_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
