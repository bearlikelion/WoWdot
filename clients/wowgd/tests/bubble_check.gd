class_name BubbleCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 10000
const SPOKEN: String = "Chat bubbles work"

var _failures: PackedStringArray = []
var _main: Main


# Says a line and watches for the bubble it raises over the player.
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
	var bubbles: ChatBubbles = _main.world.find_child("ChatBubbles", true, false)
	WowClient.session.send_chat(WowSession.CHAT_SAY, SPOKEN)
	var raised: bool = await _until(func() -> bool: return _bubble(bubbles) != null)
	_check(raised, "saying something raises a bubble")
	if raised:
		var bubble: Control = _bubble(bubbles)
		_check(bubble.size.x > 0.0 and bubble.size.y > 0.0, "the bubble is sized to its text")
		# An unloaded texture draws as a plain white rectangle.
		var backdrop: WowBackdrop = bubble.get_node("Backdrop")
		_check(backdrop.background.get_rid().is_valid() and backdrop.edge.get_rid().is_valid(),
				"the bubble's backdrop textures loaded")
		var shown: bool = await _until(func() -> bool: return bubble.visible)
		_check(shown, "the bubble follows the speaker on screen")
		await _frames(5)
		_capture("user://chat_bubble.png")
	WowClient.session.send_chat(WowSession.CHAT_PARTY, SPOKEN)
	await _frames(30)
	_check(_bubbles_up(bubbles) == 1, "party chat raises no bubble")
	_finish("")


func _capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))


func _bubbles_up(bubbles: ChatBubbles) -> int:
	return bubbles.get_child_count()


func _bubble(bubbles: ChatBubbles) -> Control:
	for child: Node in bubbles.get_children():
		if (child.get_node("%Text") as Label).text == SPOKEN:
			return child
	return null


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
	print("bubble_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
