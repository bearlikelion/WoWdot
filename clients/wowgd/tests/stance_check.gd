class_name StanceCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 10000
const BATTLE_STANCE: int = 2457
const DEFENSIVE_STANCE: int = 71
const FORM_BATTLE: int = 17
const FORM_DEFENSIVE: int = 18
const STANCE_COOLDOWN_SECONDS: float = 1.5

var _failures: PackedStringArray = []
var _main: Main


# A warrior's stances fill the bar, switch the form and move the action bar to its bonus page.
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
	for spell: int in [BATTLE_STANCE, DEFENSIVE_STANCE]:
		if not session.get_known_spells().has(spell):
			session.send_chat(WowSession.CHAT_SAY, ".learn %d" % spell)
	if not await _until(func() -> bool: return session.get_known_spells().has(DEFENSIVE_STANCE)):
		return _finish("the character never learned the stances")
	await _frames(10)
	var bar: StanceBar = _main.world.hud().find_child("ShapeshiftBarFrame", true, false)
	_check(bar != null and bar.visible, "the stance bar shows once stances are known")
	if bar == null:
		return _finish("no stance bar")
	var buttons: Array[Node] = bar.find_children("ShapeshiftButton*", "", false, false)
	var shown: int = 0
	for button: Node in buttons:
		shown += int((button as Control).visible)
	_check(shown == 2, "a button per stance is shown (%d)" % shown)

	_press(bar, 2)
	var defensive: bool = await _until(func() -> bool: return _form() == FORM_DEFENSIVE)
	_check(defensive, "clicking the second stance takes Defensive Stance")
	_check(_bar_page() == MainMenuBar.BONUS_PAGE_BY_FORM[FORM_DEFENSIVE],
		"Defensive Stance moves the action bar to its bonus page")
	# Stances share a cooldown, which headless frames run through far faster than real time.
	await get_tree().create_timer(STANCE_COOLDOWN_SECONDS).timeout
	_press(bar, 1)
	var battle: bool = await _until(func() -> bool: return _form() == FORM_BATTLE)
	_check(battle, "clicking the first stance takes Battle Stance")
	await _frames(5)
	_check((_button(bar, 1) as ActionButton).stance_active, "the active stance is checked")
	_finish("")


func _form() -> int:
	var session: WowSession = WowClient.session
	return (session.get_field(session.get_player_guid(), "UNIT_FIELD_BYTES_1") >> 16) & 0xFF


func _bar_page() -> int:
	var bar: MainMenuBar = _main.world.hud().find_child("MainMenuBar", true, false)
	return bar.shown_page()


func _button(bar: StanceBar, index: int) -> Node:
	return bar.get_node("ShapeshiftButton%d" % index)


func _press(bar: StanceBar, index: int) -> void:
	(_button(bar, index) as BaseButton).pressed.emit()


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
	print("stance_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
