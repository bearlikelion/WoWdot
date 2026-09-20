class_name FriendsCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 10000
# Another character on the account, so the list has someone real in it.
const FRIEND: String = "Mogue"

var _failures: PackedStringArray = []
var _main: Main
var _lines: PackedStringArray = []


# Adds a friend, sees them listed, then removes them again.
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
	var hud: Hud = _main.world.hud()
	var friends: FriendsFrame = hud.find_child("FriendsFrame", true, false)
	friends.message_added.connect(func(text: String) -> void: _lines.append(text))
	hud.find_child("MainMenuBar", true, false).panel_toggled.emit(
		MainMenuBar.GamePanel.SOCIAL
	)
	await _frames(20)
	_check(friends.visible, "the social button opens the friends window")
	friends.add(FRIEND)
	var added: bool = await _until(func() -> bool: return _row_named(friends, FRIEND) >= 0)
	_check(added, "adding a friend lists them")
	if added:
		(friends.get_node("%%FriendsFrameFriendButton%d" % (_row_named(friends, FRIEND) + 1)) \
		as BaseButton).pressed.emit()
		await _frames(5)
		(friends.get_node("%FriendsFrameRemoveFriendButton") as BaseButton).pressed.emit()
		var removed: bool = await _until(func() -> bool: return _row_named(friends, FRIEND) < 0)
		_check(removed, "removing a friend takes them off the list")
	friends.show_tab(FriendsFrame.Tab.IGNORE)
	await _frames(20)
	friends.add(FRIEND)
	var ignored: bool = await _until(func() -> bool: return _row_named(friends, FRIEND) >= 0)
	_check(ignored, "ignoring a player lists them")
	if ignored:
		(friends.get_node("%%FriendsFrameFriendButton%d" % (_row_named(friends, FRIEND) + 1)) \
		as BaseButton).pressed.emit()
		await _frames(5)
		(friends.get_node("%FriendsFrameRemoveFriendButton") as BaseButton).pressed.emit()
		var unignored: bool = await _until(func() -> bool: return _row_named(friends, FRIEND) < 0)
		_check(unignored, "unignoring takes them off the list")
	_finish("")


func _row_text(friends: FriendsFrame, index: int) -> String:
	var label: Label = friends.get_node(
		"%%FriendsFrameFriendButton%dButtonTextNameLocation" % (index + 1)
	)
	return label.text


func _row_named(friends: FriendsFrame, player_name: String) -> int:
	for i: int in FriendsFrame.ROWS:
		var row: Control = friends.get_node("%%FriendsFrameFriendButton%d" % (i + 1))
		if row.visible and _row_text(friends, i) == player_name:
			return i
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
	print("friends_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
