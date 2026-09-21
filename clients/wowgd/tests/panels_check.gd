class_name PanelsCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
# Coldridge Valley's Dwarven Outfitters (an item objective) and A New Threat (two kill objectives).
const STARTER_QUESTS: Array[int] = [179, 170]

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
	await _frames(20)
	var first_header: Label = character.get_node("%SkillTypeLabel1Text")
	var first_skill: Label = character.get_node("%SkillRankFrame2SkillName")
	var first_rank: Label = character.get_node("%SkillRankFrame2SkillRank")
	print("skills: '%s', '%s' %s" % [first_header.text, first_skill.text, first_rank.text])
	_check(not first_header.text.is_empty() and not first_skill.text.is_empty(), "skills list")
	(character.get_node("%SkillRankFrame2Border") as BaseButton).pressed.emit()
	await _frames(10)
	_capture("user://panels_skills.png")
	await _press(KEY_U)
	var reputation: bool = character.current_tab() == CharacterFrame.Tab.REPUTATION
	_check(character.visible and reputation, "U shows reputation")
	await _frames(20)
	var faction: Label = character.get_node("%ReputationBar2FactionName")
	var standing: Label = character.get_node("%ReputationBar2FactionStanding")
	print("reputation: '%s' '%s' '%s'" % [
		(character.get_node("%ReputationHeader1NormalText") as Label).text, faction.text,
		standing.text,
	])
	_check(not faction.text.is_empty() and not standing.text.is_empty(), "factions list")
	_capture("user://panels_reputation.png")
	await _watch_bar(character, faction.text)
	await _press(KEY_U)
	_check(not character.visible, "U again closes the frame")
	await _press(KEY_K)
	await _press(KEY_K)
	_check(not character.visible, "K again closes the frame")
	await _press(KEY_N)
	var talents: TalentFrame = panels.get_node("%TalentFrame")
	_check(talents.visible, "N opens the talents")
	var tab_name: Label = talents.get_node("%TalentFrameTab1Text")
	var first_talent: ItemButton = talents.get_node("%TalentFrameTalent1")
	print("talents: first tab '%s', spent '%s'" % [
		tab_name.text, (talents.get_node("%TalentFrameSpentPoints") as Label).text,
	])
	_check(not tab_name.text.is_empty() and first_talent.visible, "the talent tree fills in")
	await _frames(20)
	_capture("user://panels_talents.png")
	(talents.get_node("%TalentFrameTab2") as BaseButton).pressed.emit()
	await _frames(20)
	_capture("user://panels_talents_2.png")
	await _press(KEY_N)
	_check(not talents.visible, "N again closes the talents")
	await _check_quest_log(hud, panels)
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
	(game_menu.get_node("%GameMenuButtonUIOptions") as BaseButton).pressed.emit()
	await _frames(20)
	var options: UIOptionsFrame = panels.get_node("%UIOptionsFrame")
	_check(options.visible, "the game menu opens the interface options")
	_capture("user://panels_interface_options.png")
	var names: WowButton = options.get_node("%UIOptionsFrameCheckButton21")
	names.pressed.emit()
	await _frames(20)
	_check(
		not WowAssets.interface.is_on(&"show_player_names"),
		"unticking Show Player Names moves the setting",
	)
	names.pressed.emit()
	await _frames(10)
	(options.get_node("%UIOptionsFrameCancel") as BaseButton).pressed.emit()
	await _frames(20)
	_check(game_menu.visible, "closing the options goes back to the game menu")
	(game_menu.get_node("%GameMenuButtonKeybindings") as BaseButton).pressed.emit()
	await _frames(20)
	var bindings: KeyBindingFrame = panels.get_node("%KeyBindingFrame")
	_check(bindings.visible, "the game menu opens the key bindings")
	_capture("user://panels_key_bindings.png")
	(bindings.get_node("%KeyBindingFrameCancelButton") as BaseButton).pressed.emit()
	await _frames(20)
	_check(game_menu.visible, "closing the bindings goes back to the game menu")
	await _press(KEY_ESCAPE)
	_check(not game_menu.visible, "Escape closes the game menu")
	await _press(KEY_M)
	var world_map: WorldMapFrame = panels.get_node("%WorldMapFrame")
	_check(world_map.visible, "M opens the world map")
	await _frames(40)
	var zone_markers: int = (world_map.get("_markers") as Array).size()
	print("world map: area %d, %d markers" % [world_map.get("_shown"), zone_markers])
	_check(zone_markers > 0, "the zone map shows points of interest")
	_capture("user://panels_world_map.png")
	(world_map.get_node("%WorldMapZoomOutButton") as BaseButton).pressed.emit()
	await _frames(40)
	print("continent: area %d, %d markers" % [
		world_map.get("_shown"), (world_map.get("_markers") as Array).size(),
	])
	_capture("user://panels_continent.png")
	await _press(KEY_M)
	_check(not world_map.visible, "M again closes the world map")
	_finish("")


# GM-added starter quests fill the log with L, then Abandon and the popup take them out again.
func _check_quest_log(hud: Hud, panels: PanelManager) -> void:
	var session: WowSession = WowClient.session
	var before: int = QuestLog.slots().size()
	for quest: int in STARTER_QUESTS:
		session.send_chat(WowSession.CHAT_SAY, ".quest add %d" % quest)
	var give_up: int = Time.get_ticks_msec() + 5000
	while QuestLog.slots().size() < before + STARTER_QUESTS.size():
		if Time.get_ticks_msec() > give_up:
			_check(false, "the GM command added the starter quests")
			return
		await get_tree().process_frame
	await _press(KEY_L)
	var quest_log: QuestLogFrame = panels.get_node("%QuestLogFrame")
	_check(quest_log.visible, "L opens the quest log")
	await _frames(60)
	var header: Label = quest_log.get_node("%QuestLogTitle1NormalText")
	var quest_title: Label = quest_log.get_node("%QuestLogQuestTitle")
	var objective: Label = quest_log.get_node("%QuestLogObjective1")
	print("quest log: header '%s', selected '%s', objective '%s', count '%s'" % [
		header.text, quest_title.text, objective.text,
		(quest_log.get_node("%QuestLogQuestCount") as Label).text,
	])
	var listed: bool = not header.text.is_empty() and quest_title.text != "Quest title"
	_check(listed, "the quest log lists and selects quests")
	_capture("user://panels_quest_log.png")
	var details: WowScrollFrame = quest_log.get_node("%QuestLogDetailScrollFrame")
	details.scroll_to(INF)
	await _frames(5)
	_capture("user://panels_quest_rewards.png")
	(quest_log.get_node("%QuestLogTitle3") as BaseButton).pressed.emit()
	await _frames(30)
	print("second quest: '%s', objective '%s'" % [quest_title.text, objective.text])
	_capture("user://panels_quest_log_2.png")
	var watch: QuestWatchFrame = hud.get_node("%QuestWatchFrame")
	for pressed: bool in [true, false]:
		var shift: InputEventKey = InputEventKey.new()
		shift.keycode = KEY_SHIFT
		shift.physical_keycode = KEY_SHIFT
		shift.pressed = pressed
		Input.parse_input_event(shift)
		await _frames(2)
		if pressed:
			(quest_log.get_node("%QuestLogTitle2") as BaseButton).pressed.emit()
	await _frames(20)
	var watch_title: Label = watch.get_node("%QuestWatchLine1")
	var watch_line: Label = watch.get_node("%QuestWatchLine2")
	print("tracker: '%s' '%s'" % [watch_title.text, watch_line.text])
	_check(watch.visible and not watch_title.text.is_empty(), "shift-click tracks a quest")
	var check: CanvasItem = quest_log.get_node("%QuestLogTitle2Check")
	_check(check.visible, "tracked quests show a check")
	_capture("user://panels_tracker.png")
	var popup: StaticPopup = panels.get_node("%StaticPopup1")
	for i: int in STARTER_QUESTS.size():
		(quest_log.get_node("%QuestLogFrameAbandonButton") as BaseButton).pressed.emit()
		await _frames(10)
		_check(popup.visible, "Abandon asks first")
		if i == 0:
			print("popup: '%s'" % (popup.get_node("%StaticPopup1Text") as Label).text)
			_capture("user://panels_abandon.png")
		(popup.get_node("%StaticPopup1Button1") as BaseButton).pressed.emit()
		await _frames(60)
	_check(QuestLog.slots().size() == before, "Yes abandons the quests")
	await _press(KEY_L)
	_check(not quest_log.visible, "L again closes the quest log")


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


# Watching a faction puts it on the main bar, and unwatching takes it off again.
func _watch_bar(character: CharacterFrame, faction_name: String) -> void:
	var watch_bar: Control = _main.world.hud().find_child("ReputationWatchBar", true, false)
	var text: Label = watch_bar.find_child("ReputationWatchStatusBarText", true, false)
	(character.get_node("%ReputationBar2") as Control).gui_input.emit(_click())
	await _frames(10)
	(character.get_node("%ReputationDetailMainScreenCheckBox") as BaseButton).pressed.emit()
	var watched: bool = await _until(func() -> bool: return watch_bar.visible)
	_check(watched, "watching a faction shows the reputation bar")
	_check(text.text.begins_with(faction_name), "the bar names the faction (%s)" % text.text)
	(character.get_node("%ReputationDetailMainScreenCheckBox") as BaseButton).pressed.emit()
	var cleared: bool = await _until(func() -> bool: return not watch_bar.visible)
	_check(cleared, "unwatching hides the reputation bar")


func _click() -> InputEventMouseButton:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = false
	return click


func _until(condition: Callable, timeout_msec: int = 5000) -> bool:
	var until: int = Time.get_ticks_msec() + timeout_msec
	while not condition.call() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	return condition.call()


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
	print("panels_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
