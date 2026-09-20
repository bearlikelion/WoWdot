class_name HunterCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 150000
const STEP_MSEC: int = 40000
const HUNTER: String = "Huntik"
# A tamed beast has to be of the hunter's level or lower.
const TAME_LEVEL: int = 10
# The spawn of a Coldridge Valley wolf, where a dwarf hunter finds something to tame.
const BEASTS_AT: String = ".go creature 332"
const PET_NAME: String = "Fangs"

var _failures: PackedStringArray = []
var _main: Main


# Tames a wolf, names it, then stables it with the Kharanos stable master.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	_main.auto_character = HUNTER
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var ready_at: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _main.world == null or not _main.world.player().active:
		if Time.get_ticks_msec() > ready_at:
			return _finish("never reached the world")
		await get_tree().process_frame
	await _frames(60)
	if _main.world == null:
		return _finish("the world went away before the check started")
	var session: WowSession = WowClient.session
	var hud: Hud = _main.world.hud()
	var pet: Pet = WowClient.pet
	var pet_frame: PetFrame = hud.find_child("PetFrame", true, false)
	var popup: StaticPopup = hud.get_node("%UIPanels").get_node("%StaticPopup1")
	session.chat_received.connect(func(line: Dictionary) -> void:
		if line["type"] == WowSession.CHAT_SYSTEM:
			printerr("system: %s" % line["text"])
	)
	session.spell_cast_failed.connect(
		func(_caster: int, spell_id: int, reason: int) -> void:
			printerr("cast %d failed: %d" % [spell_id, reason])
	)
	# A character that has only just logged in is still settling into the world.
	await get_tree().create_timer(3.0).timeout
	session.send_chat(WowSession.CHAT_SAY, ".character level %s %d" % [HUNTER, TAME_LEVEL])
	session.send_chat(WowSession.CHAT_SAY, BEASTS_AT)
	await get_tree().create_timer(5.0).timeout
	if pet.guid != 0:
		pet.dismiss()
		await _until(func() -> bool: return pet.guid == 0)
	if not await _tame(session, pet):
		return _finish("no wolf was tamed")
	_check(await _until(func() -> bool: return pet_frame.visible), "the pet frame shows the pet")
	_check(
		await _until(func() -> bool: return popup.visible), "a tamed pet asks for a name"
	)
	if popup.visible:
		(popup.get_node("%StaticPopup1EditBox") as LineEdit).text = PET_NAME
		(popup.get_node("%StaticPopup1Button1") as BaseButton).pressed.emit()
		_check(
			await _until(func() -> bool:
				return (pet_frame.get_node("%PetName") as Label).text == PET_NAME),
			"the named pet wears its new name",
		)
	_check(
		await _until(func() -> bool:
			return (pet_frame.get_node("%PetFrameHappiness") as Control).visible),
		"a hunter pet shows its happiness",
	)
	await _check_spell_book(hud, pet)
	await _stable(session, hud, pet)
	_finish("")


# The pet book is the spellbook's second tab, holding what the pet itself can cast.
func _check_spell_book(hud: Hud, pet: Pet) -> void:
	var book: SpellBook = hud.get_node("%UIPanels").get_node("%SpellBookFrame")
	hud.find_child("MainMenuBar", true, false).panel_toggled.emit(
		MainMenuBar.GamePanel.SPELLBOOK
	)
	await _frames(20)
	_check(not pet.spells.is_empty(), "the pet knows spells of its own")
	(book.get_node("%SpellBookFrameTabButton2") as BaseButton).pressed.emit()
	await _frames(20)
	_check(
		(book.get_node("%SpellButton1SpellName") as Label).text != "",
		"the pet book lists the pet's spells",
	)
	hud.find_child("MainMenuBar", true, false).panel_toggled.emit(
		MainMenuBar.GamePanel.SPELLBOOK
	)


# .stable is the stable master without the walk: the server lists the pets for the player itself.
func _stable(session: WowSession, hud: Hud, pet: Pet) -> void:
	var stable: PetStableFrame = hud.get_node("%UIPanels").get_node("%PetStableFrame")
	# A stable slot has to be bought before a pet can go into it, and it costs five silver.
	session.send_chat(WowSession.CHAT_SAY, ".modify money 100000")
	session.send_chat(WowSession.CHAT_SAY, ".stable")
	_check(await _until(func() -> bool: return stable.visible), "the stable lists the pets")
	if not stable.visible:
		return
	var slot: BaseButton = stable.get_node("%PetStableStabledPet1")
	(stable.get_node("%PetStablePurchaseButton") as BaseButton).pressed.emit()
	_check(
		await _until(func() -> bool: return (slot as Control).visible),
		"buying a slot opens it in the stable",
	)
	slot.pressed.emit()
	_check(
		await _until(func() -> bool: return pet.guid == 0), "clicking a free slot stables the pet"
	)
	session.send_chat(WowSession.CHAT_SAY, ".stable")
	await get_tree().create_timer(2.0).timeout
	slot.pressed.emit()
	_check(await _until(func() -> bool: return pet.guid != 0), "clicking the pet brings it back")


# Beasts live around the wolf spawn, and .npc tame turns down anything that cannot be tamed.
func _tame(session: WowSession, pet: Pet) -> bool:
	for attempt: int in 3:
		for unit: int in _units_near(session):
			_main.world.select(unit)
			# The server needs the selection first, and frames are not wall clock in a headless run.
			await get_tree().create_timer(1.0).timeout
			session.send_chat(WowSession.CHAT_SAY, ".npc tame")
			if await _until(
				func() -> bool: return pet.guid != 0 and session.has_object(pet.guid), 6000
			):
				return true
		await get_tree().create_timer(5.0).timeout
	return false


# Every unit in the world the client knows, nearest first, the player left out.
func _units_near(session: WowSession) -> Array[int]:
	var player: Vector3 = WowCoords.from_godot(_main.world.player().global_position)
	var units: Array[int] = []
	for guid: int in session.get_object_guids():
		if session.get_object_type(guid) == Entities.ObjectType.UNIT \
		and session.get_field(guid, "UNIT_FIELD_HEALTH") > 0:
			units.append(guid)
	units.sort_custom(func(a: int, b: int) -> bool:
		return session.get_object_position(a).distance_to(player) \
		< session.get_object_position(b).distance_to(player)
	)
	return units


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
	print("hunter_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
