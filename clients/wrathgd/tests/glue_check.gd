class_name GlueCheck
extends Node

# Can I Keep Him?, which a GM can grant outright.
const GUILD: String = "Wrathglue Bank"
# A Guild Vault, gameobject type 34.
const GUILD_VAULT: int = 187289
# Enough for the first tab's hundred gold.
const GUILD_BANK_MONEY: int = 1000000
const COPPER: int = 1234
const ARENA_TEAM: String = "Wrathglue Arena"
const ACHIEVEMENT: int = 1017
# CharTitles 1, Private, whose known-titles bit is also 1.
const TITLE: int = 1
const TITLE_BIT: int = 1
const TITLE_NAME: String = "Private"
const GEAR_SET: String = "Gluecheck"
const GLYPH: int = 43397
const GLYPH_LEVEL: int = 15
# Glyph of Charge is minor, and the second socket is the first minor one.
const GLYPH_SOCKET: int = 1
const WATER: int = 159
const DRINK_SPELL: int = 430
const MAIN: PackedScene = preload("res://game/main.tscn")
const STEP_TIMEOUT_MSEC: int = 120000
# The local AzerothCore stack answers on the shifted ports.
const REALMLIST: String = "127.0.0.1:3725"
const ACCOUNT: String = "wowgd"
const PASSWORD: String = "wowgd"
const CHARACTER: String = "Wrathglue"

var _failures: PackedStringArray = []
var _main: Main
var _glue: Glue
var _select: CharacterSelect
var _create: CharacterCreate
var _characters: Array = []
var _enumerations: int = 0
var _elapsed: int = 0


# Runs the real client against AzerothCore: log in, make a character, enter the world.
func _ready() -> void:
	_main = MAIN.instantiate()
	add_child(_main)
	_glue = _main.get_node("%Glue")
	_select = _glue.get_node("%CharacterSelect")
	_create = _glue.get_node("%CharacterCreate")
	WowClient.session.characters_received.connect(_on_characters_received)
	_run.call_deferred()


func _run() -> void:
	var login: LoginScreen = _glue.get_node("%AccountLogin")
	var dialog: GlueDialog = _glue.get_node("%GlueDialog")
	_check(not (dialog.get_node("%GlueDialogButton3") as CanvasItem).visible,
			"the WotLK dialog's third button stays hidden")
	login.fill(REALMLIST, ACCOUNT, PASSWORD)
	await _frames(30)
	_capture("user://wotlk_login.png")
	# WOWDOT_MOTION samples the glue scene's loop, which runs for over a minute.
	if not OS.get_environment("WOWDOT_MOTION").is_empty():
		for second: int in [4, 10, 18, 22, 26, 40, 62]:
			await get_tree().create_timer(second - _elapsed).timeout
			_elapsed = second
			_capture("user://wotlk_login_%02d.png" % second)
	login.log_in()
	if not await _until(_select_ready, "the character screen shows"):
		return _finish()
	await _frames(30)
	_capture("user://wotlk_characters.png")
	if not await _survey_races():
		return _finish()
	if not _names().has(CHARACTER) and not await _make_character():
		return _finish()
	_select.select(_names().find(CHARACTER))
	_select.enter_world()
	if not await _until(func() -> bool: return _main.world != null, "the world scene appears"):
		return _finish()
	if not await _until(func() -> bool: return _main.world.player().active,
			"the player takes the world"):
		return _finish()
	var made: Dictionary = _character()
	print("%s, race %d class %d, in the world at %v" % [
		CHARACTER, made["race"], made["class"],
		WowCoords.from_godot(_main.world.player().global_position),
	])
	_check(WowClient.session.get_state() == WowSession.STATE_IN_WORLD,
			"the session reports being in the world")
	await _frames(60)
	_capture("user://wotlk_world.png")
	await _use_item()
	await _glyph()
	await _gear_manager()
	await _dungeon_finder()
	await _achievements()
	await _arena_team()
	await _guild_bank()
	_finish()


# A GM-made guild buys its first tab at a spawned vault, then money and a stack go in and out.
func _guild_bank() -> void:
	var session: WowSession = WowClient.session
	var bank: GuildBank = WowClient.guild_bank
	var vaults: Array[int] = []
	var on_created: Callable = func(guid: int, _type_id: int) -> void:
		if session.get_field(guid, "OBJECT_FIELD_ENTRY") == GUILD_VAULT:
			vaults.append(guid)
	session.object_created.connect(on_created)
	# A run stopped part way leaves its guild behind, which would keep the create from working.
	session.send_chat(WowSession.CHAT_SAY, '.guild delete "%s"' % GUILD)
	await _frames(30)
	session.send_chat(WowSession.CHAT_SAY, '.guild create "%s"' % GUILD)
	session.send_chat(WowSession.CHAT_SAY, ".modify money %d" % GUILD_BANK_MONEY)
	session.send_chat(WowSession.CHAT_SAY, ".additem %d %d" % [WATER, 5])
	session.send_chat(WowSession.CHAT_SAY, ".gobject add temp %d" % GUILD_VAULT)
	if not await _until(func() -> bool: return not vaults.is_empty(), "a guild vault spawns"):
		return
	bank.activate(vaults[0])
	var frame: GuildBankFrame = get_tree().root.find_child("GuildBankFrame", true, false)
	if not await _until(func() -> bool: return frame.visible, "the vault opens the guild bank"):
		return
	(frame.get_node("%GuildBankFramePurchaseButton") as BaseButton).pressed.emit()
	if not await _until(func() -> bool: return bank.tabs.size() == 1,
			"the first bank tab is bought"):
		return
	bank.query_tab(0)
	bank.deposit_money(COPPER)
	await _until(func() -> bool: return bank.money == COPPER, "money goes into the bank")
	var at: Vector2i = Inventory.find_item(WATER)
	if at.x >= 0 and frame.deposit(at.x, at.y):
		var water_slot: Callable = func() -> int:
			var slots: Array = bank.items.get(0, [])
			for slot: int in slots.size():
				if slots[slot].get("item", 0) == WATER:
					return slot
			return -1
		if await _until(func() -> bool: return water_slot.call() >= 0,
				"a bag stack goes into the bank tab"):
			await _frames(30)
			_capture("user://wotlk_guild_bank.png")
			var slot: int = water_slot.call()
			bank.withdraw_item(0, slot)
			await _until(func() -> bool: return bank.items[0][slot].is_empty(),
					"the stack comes back out of the bank")
	frame.close_requested.emit()
	session.object_created.disconnect(on_created)
	session.send_chat(WowSession.CHAT_SAY, '.guild delete "%s"' % GUILD)


# A GM-made 2v2 team shows on the PvP frame with its roster, then the captain disbands it.
func _arena_team() -> void:
	var arena: ArenaTeams = WowClient.arena_teams
	WowClient.session.send_chat(WowSession.CHAT_SAY, '.arena create "%s" 2' % ARENA_TEAM)
	if not await _until(func() -> bool: return not arena.slot_info(0).is_empty(),
			"the new arena team fills the first team slot"):
		return
	var team_id: int = arena.slot_info(0)[ArenaTeams.Info.ID]
	var press: InputEventAction = InputEventAction.new()
	press.action = "toggle_pvp"
	press.pressed = true
	Input.parse_input_event(press)
	var frame: PVPParentFrame = get_tree().root.find_child("PVPParentFrame", true, false)
	var team_name: Label = frame.get_node("%PVPTeam1DataName")
	if await _until(func() -> bool: return frame.visible and team_name.text == ARENA_TEAM,
			"the PvP frame names the 2v2 team"):
		(frame.get_node("%PVPTeam1") as BaseButton).pressed.emit()
		var member: Label = frame.get_node("%PVPTeamDetailsButton1NameText")
		await _until(func() -> bool: return member.text == CHARACTER,
				"the team roster lists the captain")
		await _frames(30)
		_capture("user://wotlk_pvp.png")
	frame.show_tab(2)
	var battlegrounds: Battlegrounds = WowClient.battlegrounds
	var first: Label = frame.get_node("%BattlegroundType1Text")
	var listed: Callable = func() -> bool:
		return not first.text.is_empty() and battlegrounds.rewards.size() > 0
	if await _until(listed, "the battleground tab lists and describes a battleground"):
		await _frames(30)
		_capture("user://wotlk_pvp_battlegrounds.png")
		(frame.get_node("%PVPBattlegroundFrameJoinButton") as BaseButton).pressed.emit()
		var queued: Callable = func() -> bool:
			return battlegrounds.queue(0).get("status", 0) == Battlegrounds.Status.WAIT_QUEUE
		if await _until(queued, "joining from the PvP frame queues the character"):
			battlegrounds.abandon(battlegrounds.queue(0)["map_id"])
	frame.close_requested.emit()
	arena.disband(team_id)
	await _until(func() -> bool: return arena.slot_info(0).is_empty(),
			"the disbanded team leaves the slot")


# A GM-granted achievement lands in the list or arrives as earned, and a granted title can be worn.
func _achievements() -> void:
	var session: WowSession = WowClient.session
	var achievements: Achievements = WowClient.achievements
	if not achievements.completed.has(ACHIEVEMENT):
		session.send_chat(WowSession.CHAT_SAY, ".achievement add %d" % ACHIEVEMENT)
		await _until(func() -> bool: return achievements.completed.has(ACHIEVEMENT),
				"the granted achievement is earned")
	_check(achievements.points() > 0, "completed achievements count their points")
	var me: int = session.get_player_guid()
	session.send_chat(WowSession.CHAT_SAY, ".titles add %d" % TITLE)
	await _frames(30)
	achievements.set_title(TITLE_BIT)
	var worn: Callable = func() -> bool:
		return session.get_field(me, "PLAYER_CHOSEN_TITLE") == TITLE_BIT
	if not await _until(worn, "the chosen title is worn"):
		return
	var character: CharacterFrame = get_tree().root.find_child("CharacterFrame", true, false)
	character.refresh()
	_check((character.get_node("%PlayerTitleFrameText") as Label).text == TITLE_NAME,
			"the paper doll names the worn title")
	achievements.set_title(TitlePickerFrame.NO_TITLE)
	await _until(func() -> bool: return session.get_field(me, "PLAYER_CHOSEN_TITLE") == 0,
			"the title comes off")
	session.send_chat(WowSession.CHAT_SAY, ".titles remove %d" % TITLE)
	var press: InputEventAction = InputEventAction.new()
	press.action = "toggle_achievements"
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(30)
	var frame: AchievementFrame = get_tree().root.find_child("AchievementFrame", true, false)
	_check(frame.visible, "the achievement key opens the achievement frame")
	var points: Label = frame.get_node("%AchievementFrameHeaderPoints")
	_check(points.text == str(achievements.points()),
			"the achievement frame shows the points earned")
	var latest: Label = frame.get_node("%AchievementFrameSummaryAchievement1Label")
	_check(not latest.text.is_empty(), "the summary lists the latest achievement")
	_capture("user://wotlk_achievements.png")
	(frame.get_node("%AchievementFrameCategoriesContainerButton2") as BaseButton).pressed.emit()
	await _frames(30)
	_capture("user://wotlk_achievements_category.png")
	frame.close_requested.emit()


# A one-player queue through the LFD frame: a proposal, the teleport in, and back out.
func _dungeon_finder() -> void:
	var session: WowSession = WowClient.session
	var finder: DungeonFinder = WowClient.dungeon_finder
	var said: PackedStringArray = []
	var maps: Array[int] = []
	session.chat_received.connect(func(line: Dictionary) -> void: said.append(line["text"]))
	session.world_entered.connect(
		func(map_id: int, _at: Vector3, _facing: float) -> void: maps.append(map_id)
	)
	if not await _set_solo_queue(true, said):
		return
	var press: InputEventAction = InputEventAction.new()
	press.action = "toggle_lfd"
	press.pressed = true
	Input.parse_input_event(press)
	var frame: LFDParentFrame = get_tree().root.find_child("LFDParentFrame", true, false)
	if await _until(func() -> bool: return not finder.random_dungeons.is_empty(),
			"the dungeon finder offers random dungeons"):
		await _frames(30)
		_capture("user://wotlk_lfd.png")
		(frame.get_node("%LFDQueueFrameFindGroupButton") as BaseButton).pressed.emit()
		var popup: LFDDungeonReadyPopup = \
				get_tree().root.find_child("LFDDungeonReadyPopup", true, false)
		if await _until(func() -> bool: return popup.visible, "the dungeon ready popup opens"):
			await _frames(30)
			_capture("user://wotlk_lfd_ready.png")
			var enter: BaseButton = popup.get_node("%LFDDungeonReadyDialogEnterDungeonButton")
			enter.pressed.emit()
			if await _until(func() -> bool: return not maps.is_empty(), "the group is sent in"):
				print("dungeon finder sent the group to map %d" % maps[0])
				finder.teleport(true)
				await _until(func() -> bool: return maps.size() > 1, "the teleport out lands")
			session.send_packet("CMSG_GROUP_DISBAND", PackedByteArray())
	await _set_solo_queue(false, said)


# .debug lfg toggles AzerothCore's one-player queue for every session, so it is set back after.
func _set_solo_queue(solo: bool, said: PackedStringArray) -> bool:
	for attempt: int in 2:
		said.clear()
		WowClient.session.send_chat(WowSession.CHAT_SAY, ".debug lfg")
		var answered: Callable = func() -> bool:
			return not said.is_empty() and said[-1].begins_with("LFG")
		if not await _until(answered, "the LFG debug toggle answers"):
			return false
		if said[-1].contains("1 player") == solo:
			return true
	return false


# The paper doll's gear manager saves a set through its popup and lists it.
func _gear_manager() -> void:
	var character: CharacterFrame = get_tree().root.find_child("CharacterFrame", true, false)
	var press: InputEventAction = InputEventAction.new()
	press.action = "toggle_character"
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(5)
	(character.get_node("%GearManagerToggleButton") as BaseButton).pressed.emit()
	(character.get_node("%GearManagerDialogSaveSet") as BaseButton).pressed.emit()
	(character.get_node("%GearManagerDialogPopupEditBox") as LineEdit).text = GEAR_SET
	(character.get_node("%GearManagerDialogPopupButton1") as BaseButton).pressed.emit()
	(character.get_node("%GearManagerDialogPopupOkay") as BaseButton).pressed.emit()
	var sets: EquipmentSets = WowClient.equipment_sets
	if await _until(func() -> bool: return sets.find(GEAR_SET).get("guid", 0) != 0,
			"the gear manager's set is saved"):
		_check((character.get_node("%GearSetButton1Name") as Label).text == GEAR_SET,
				"the first gear set button names the saved set")
		await _frames(30)
		_capture("user://wotlk_gear_manager.png")
		sets.delete(sets.find(GEAR_SET))


# A glyph used through the socket path lands in PLAYER_FIELD_GLYPHS_1, and comes out again.
func _glyph() -> void:
	var session: WowSession = WowClient.session
	var me: int = session.get_player_guid()
	if session.get_field(me, "UNIT_FIELD_LEVEL") < GLYPH_LEVEL:
		session.send_chat(WowSession.CHAT_SAY, ".levelup %d" % (GLYPH_LEVEL - 1))
		if not await _until(
				func() -> bool: return session.get_field(me, "UNIT_FIELD_LEVEL") >= GLYPH_LEVEL,
				"the character reaches glyph level"):
			return
	session.send_chat(WowSession.CHAT_SAY, ".additem %d" % GLYPH)
	if not await _until(func() -> bool: return Inventory.find_item(GLYPH).x >= 0, "the glyph arrives"):
		return
	await _until(func() -> bool: return not session.get_item_info(GLYPH).is_empty(), "the glyph's query")
	var at: Vector2i = Inventory.find_item(GLYPH)
	WowClient.targeting.begin_glyph(Inventory.wire_address(at.x, at.y))
	WowClient.targeting.place_glyph(GLYPH_SOCKET)
	var field: int = session.field_index("PLAYER_FIELD_GLYPHS_1") + GLYPH_SOCKET
	if not await _until(func() -> bool: return session.get_field(me, field) != 0,
			"the glyph goes into the first minor socket"):
		return
	var payload: PackedByteArray = [GLYPH_SOCKET, 0, 0, 0]
	session.send_packet("CMSG_REMOVE_GLYPH", payload)
	await _until(func() -> bool: return session.get_field(me, field) == 0,
			"removing the glyph empties the socket")


# CMSG_USE_ITEM in the 3.3.5 layout: a drink the server accepts puts its aura on the player.
func _use_item() -> void:
	var session: WowSession = WowClient.session
	session.send_chat(WowSession.CHAT_SAY, ".additem %d" % WATER)
	if not await _until(func() -> bool: return Inventory.find_item(WATER).x >= 0, "the water arrives"):
		return
	var at: Vector2i = Inventory.find_item(WATER)
	if not await _until(func() -> bool: return not session.get_item_info(WATER).is_empty(),
			"the water's item query answers"):
		return
	ItemTargeting.use_item(Inventory.wire_address(at.x, at.y))
	var me: int = session.get_player_guid()
	await _until(func() -> bool:
		for aura: Dictionary in session.get_auras(me):
			if aura["spell"] == DRINK_SPELL:
				return true
		return false, "using the water starts the drink")


# Every race 3.3.5 offers, its classes out of CharBaseInfo and the scene behind it.
func _survey_races() -> bool:
	(_select.get_node("%CharSelectCreateCharacterButton") as BaseButton).pressed.emit()
	if not await _until(func() -> bool: return _create.visible, "the create screen opens"):
		return false
	var order: Array[int] = CharacterOptions.race_order()
	_check(order.size() == 10, "the create screen offers ten races")
	for index: int in order.size():
		var race: int = order[index]
		(_create.get_node("%%CharacterCreateRaceButton%d" % (index + 1)) as BaseButton) \
				.pressed.emit()
		await _frames(2)
		_capture("user://wotlk_create_%02d.png" % race)
		var classes: Array[int] = CharacterOptions.classes_for(race)
		var label: String = (_create.get_node("%CharacterCreateRaceLabel") as Label).text
		_check(label == CharacterOptions.race_name(race),
				"the screen names race %d, showing '%s'" % [race, label])
		_check(not classes.is_empty(), "race %d offers a class" % race)
		var blurb: String = (_create.get_node("%CharacterCreateRaceText") as Label).text
		_check(not blurb.contains("|n"), "race %d reads its blurb with real line breaks" % race)
		var names: PackedStringArray = []
		for class_id: int in classes:
			names.append(CharacterOptions.class_label(class_id))
		print("  %-12s %s" % [CharacterOptions.race_name(race), ", ".join(names)])
	await _frames(10)
	_capture("user://wotlk_create.png")
	(_create.get_node("%CharCreateBackButton") as BaseButton).pressed.emit()
	return await _until(_select_ready, "the character screen comes back")


func _make_character() -> bool:
	(_select.get_node("%CharSelectCreateCharacterButton") as BaseButton).pressed.emit()
	if not await _until(func() -> bool: return _create.visible, "the create screen opens"):
		return false
	(_create.get_node("%CharacterCreateNameEdit") as LineEdit).text = CHARACTER
	(_create.get_node("%CharCreateOkayButton") as BaseButton).pressed.emit()
	return await _until(func() -> bool: return _select_ready() and _names().has(CHARACTER),
			"%s is created" % CHARACTER)


func _select_ready() -> bool:
	return _select.visible and _enumerations > 0


func _on_characters_received(characters: Array) -> void:
	_characters = characters
	_enumerations += 1


func _character() -> Dictionary:
	for character: Dictionary in _characters:
		if character["name"] == CHARACTER:
			return character
	return {}


func _names() -> PackedStringArray:
	var names: PackedStringArray = []
	for character: Dictionary in _characters:
		names.append(character["name"])
	return names


func _until(condition: Callable, what: String) -> bool:
	var give_up: int = Time.get_ticks_msec() + STEP_TIMEOUT_MSEC
	while not condition.call():
		if WowClient.session.get_state() == WowSession.STATE_FAILED:
			_failures.append("%s (session failed)" % what)
			return false
		if Time.get_ticks_msec() > give_up:
			_failures.append(what)
			return false
		await get_tree().process_frame
	return true


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


# Written only when a window is up, since a headless viewport has no texture.
func _capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if get_viewport().get_texture() == null:
		return
	# A locked screen never asks for a frame, so draw one instead of saving the last one from before.
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))


func _check(condition: bool, what: String) -> bool:
	if not condition:
		_failures.append(what)
	return condition


func _finish() -> void:
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("glue_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
