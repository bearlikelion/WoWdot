class_name PanelsCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000

var _failures: PackedStringArray = []
var _main: Main


# Opens the bags and the character frame with their keys, then walks the Escape chain.
func _ready() -> void:
	_main = MAIN.instantiate()
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
	await _frames(60)
	var hud: Hud = _main.world.hud()
	var panels: PanelManager = hud.get_node("%UIPanels")
	var character: CharacterFrame = panels.get_node("%CharacterFrame")
	var game_menu: Control = panels.get_node("%GameMenuFrame")
	await _press(KEY_B)
	var open_bags: Array[Node] = panels.find_children("*", "ContainerFrame", false, false).filter(
		func(node: Node) -> bool: return (node as Control).visible
	)
	print("bags open after B: %d" % open_bags.size())
	_check(open_bags.size() >= 1, "B opens the bags")
	var backpack: ContainerFrame = open_bags[0]
	if Inventory.container_item(Inventory.BACKPACK, 0) != 0:
		var slot_button: ItemButton = backpack.slot_button(0)
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		var center: Vector2 = slot_button.get_global_rect().get_center()
		motion.position = get_viewport().get_final_transform() * center
		Input.parse_input_event(motion)
		await _frames(10)
		var tooltip: GameTooltip = GameTooltip.current
		var first_line: Label = tooltip.get_node("%Lines").get_child(0).get_node("%Left")
		print("tooltip over the first backpack slot: '%s'" % first_line.text)
		_check(tooltip.visible and not first_line.text.is_empty(), "a bag item shows its tooltip")
		_capture("user://panels_tooltip.png")
	await _press(KEY_C)
	_check(character.visible, "C opens the character frame")
	await _frames(30)
	_capture("user://panels_open.png")
	await _press(KEY_P)
	var book: SpellBook = panels.get_node("%SpellBookFrame")
	_check(book.visible, "P opens the spellbook")
	_check(character.visible, "the spellbook opens beside the character frame")
	var first_spell: Label = book.get_node("%SpellButton1SpellName")
	var arms: WowButton = book.get_node("%SpellBookSkillLineTab2")
	print("spellbook: first spell '%s', second tab shown=%s" % [first_spell.text, arms.visible])
	_check(not first_spell.text.is_empty(), "the spellbook lists spells")
	await _frames(20)
	_capture("user://panels_spellbook.png")
	arms.pressed.emit()
	await _frames(5)
	print("second tab first spell '%s'" % first_spell.text)
	_capture("user://panels_spellbook_class.png")
	await _check_drag_to_bar(hud, book)
	await _press(KEY_P)
	_check(not book.visible, "P again closes the spellbook")
	await _press(KEY_K)
	var skills: bool = character.current_tab() == CharacterFrame.Tab.SKILLS
	_check(character.visible and skills, "K shows skills")
	await _press(KEY_K)
	_check(not character.visible, "K again closes the frame")
	await _press(KEY_F1)
	await _press(KEY_ESCAPE)
	var still_open: bool = open_bags.any(func(node: Node) -> bool: return (node as Control).visible)
	_check(not still_open, "Escape closes the bags")
	_check(hud.target() != 0, "the first Escape leaves the target alone")
	await _press(KEY_ESCAPE)
	_check(hud.target() == 0, "the next Escape clears the target")
	await _press(KEY_ESCAPE)
	_check(game_menu.visible, "Escape with nothing left opens the game menu")
	await _frames(10)
	_capture("user://panels_menu.png")
	await _press(KEY_ESCAPE)
	_check(not game_menu.visible, "Escape closes the game menu")
	_finish("")


# A spell dragged from the book onto an empty action button lands, and dragging it off clears it.
func _check_drag_to_bar(hud: Hud, book: SpellBook) -> void:
	var bar: MainMenuBar = hud.get_node("%MainMenuBar")
	var target: ActionButton = null
	for i: int in MainMenuBar.BUTTONS_PER_PAGE:
		var candidate: ActionButton = bar.get_node("%%ActionButton%d" % (i + 1))
		if candidate.spell() == 0:
			target = candidate
	var source: SpellButton = book.get_node("%SpellButton3")
	if target == null or source.spell_id == 0:
		print("no empty action button or no spell to drag; skipping the drag check")
		return
	await _drag(source, target.get_global_rect().get_center())
	await _frames(30)
	var dropped: String = WowAssets.spells.spell_name(target.spell())
	print("dropped %s on action slot %d" % [dropped, target.slot])
	_check(target.spell() == source.spell_id, "the dropped spell shows on the action bar")
	await _drag(target, get_viewport().get_visible_rect().get_center())
	await _frames(30)
	_check(target.spell() == 0, "dragging the action off the bar clears the slot")


# A left-button drag through the input system, from the control's middle to a canvas point.
func _drag(from: Control, to: Vector2) -> void:
	var screen: Transform2D = get_viewport().get_final_transform()
	var start: Vector2 = from.get_global_rect().get_center()
	var steps: Array[Vector2] = [start, start + Vector2(12.0, 12.0), to]
	for i: int in steps.size():
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = screen * steps[i]
		# The viewport starts a drag once the accumulated relative motion passes its threshold.
		motion.relative = motion.position - screen * steps[i - 1] if i > 0 else Vector2.ZERO
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT if i > 0 else 0
		Input.parse_input_event(motion)
		if i == 0:
			var press: InputEventMouseButton = InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.position = motion.position
			press.pressed = true
			Input.parse_input_event(press)
		await _frames(3)
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = screen * to
	Input.parse_input_event(release)
	await _frames(3)


func _press(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(3)


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _capture(path: String) -> void:
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
	print("panels_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
