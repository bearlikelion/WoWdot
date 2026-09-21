class_name PetCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 150000
const STEP_MSEC: int = 30000
# Warlocks learn Summon Imp from a trainer, so the check hands it over with a GM command.
const SUMMON_IMP: int = 688
const WARLOCK: String = "Warlik"

var _failures: PackedStringArray = []
var _main: Main


# Summons a warlock's imp, then works the pet frame and the pet bar.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = "127.0.0.1"
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	_main.auto_character = WARLOCK
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
	var pet_frame: PetFrame = hud.find_child("PetFrame", true, false)
	var bar: PetActionBar = hud.find_child("PetActionBarFrame", true, false)
	session.spell_cast_failed.connect(
		func(_caster: int, spell_id: int, reason: int) -> void:
			printerr("cast %d failed: %d" % [spell_id, reason])
	)
	session.send_chat(WowSession.CHAT_SAY, ".learn %d" % SUMMON_IMP)
	_check(
		await _until(func() -> bool: return session.get_known_spells().has(SUMMON_IMP)),
		"the warlock learns Summon Imp",
	)
	# A character that just logged in is still settling, and moving cancels the summon.
	await get_tree().create_timer(3.0).timeout
	# The server brings back the pet of an earlier run at login, and summoning again dismisses it.
	if _pet(session) != 0:
		WowClient.pet.dismiss()
		await _until(func() -> bool: return _pet(session) == 0)
	session.cast_spell(SUMMON_IMP)
	var summoned: bool = await _until(func() -> bool:
		return _pet(session) != 0 and session.has_object(_pet(session))
	)
	_check(summoned, "casting Summon Imp gives the warlock a pet")
	if not summoned:
		return _finish("")
	_check(await _until(func() -> bool: return pet_frame.visible), "the pet frame shows the pet")
	_check(await _until(func() -> bool: return bar.visible), "the pet action bar shows")
	_check(
		(pet_frame.get_node("%PetName") as Label).text == "Imp", "the pet frame names the pet"
	)
	_check(
		(pet_frame.get_node("%PetFrameHealthBar") as TextureProgressBar).value > 0.0,
		"the pet frame has the pet's health",
	)
	var commands: int = 0
	for i: int in Pet.BAR_SLOTS:
		var button: ActionButton = bar.get_node("%%PetActionButton%d" % (i + 1))
		if button.visible and not button.command_icon.is_empty():
			commands += 1
	_check(commands >= 6, "the bar holds the pet's commands and reactions")
	_check(not WowClient.pet.spells.is_empty(), "the imp knows spells of its own")
	await _check_spell_book(hud)
	_check_autocast(bar)
	WowClient.pet.dismiss()
	_check(
		await _until(func() -> bool: return _pet(session) == 0), "dismissing sends the pet away"
	)
	_check(await _until(func() -> bool: return not bar.visible), "the pet action bar goes away")
	_finish("")


# The pet book is the spellbook's second tab, holding what the pet itself can cast.
func _check_spell_book(hud: Hud) -> void:
	var book: SpellBook = hud.get_node("%UIPanels").get_node("%SpellBookFrame")
	hud.find_child("MainMenuBar", true, false).panel_toggled.emit(
		MainMenuBar.GamePanel.SPELLBOOK
	)
	await _frames(20)
	(book.get_node("%SpellBookFrameTabButton2") as BaseButton).pressed.emit()
	await _frames(20)
	_check(
		(book.get_node("%SpellButton1SpellName") as Label).text != "",
		"the pet book lists the pet's spells",
	)
	hud.find_child("MainMenuBar", true, false).panel_toggled.emit(
		MainMenuBar.GamePanel.SPELLBOOK
	)


# Right-clicking a pet spell on the bar turns its own casting on and off.
func _check_autocast(bar: PetActionBar) -> void:
	var pet: Pet = WowClient.pet
	for i: int in Pet.BAR_SLOTS:
		if i >= pet.actions.size():
			break
		var state: Pet.ActionState = pet.state_of(pet.actions[i])
		if state != Pet.ActionState.ENABLED and state != Pet.ActionState.DISABLED:
			continue
		var button: ActionButton = bar.get_node("%%PetActionButton%d" % (i + 1))
		var was: bool = button.stance_active
		button.gui_input.emit(_right_click())
		_check(button.stance_active != was, "a right-click toggles a pet spell's autocast")
		button.gui_input.emit(_right_click())
		return
	_check(false, "the bar holds a pet spell to autocast")


func _right_click() -> InputEventMouseButton:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	return click


func _pet(session: WowSession) -> int:
	return session.get_field_guid(session.get_player_guid(), "UNIT_FIELD_SUMMON")


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
	print("pet_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
