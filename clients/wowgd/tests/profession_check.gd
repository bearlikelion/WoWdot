class_name ProfessionCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 15000
# Blacksmithing, and the first thing it makes: one Rough Stone becomes one sharpening stone.
const BLACKSMITHING: int = 164
const APPRENTICE: int = 2018
const RECIPE: int = 2660
const ROUGH_STONE: int = 2835
const SHARPENING_STONE: int = 2862

var _failures: PackedStringArray = []
var _main: Main


# 1.12 has no tradeskill opcodes: a recipe is read out of the DBCs and made by casting its spell.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = "127.0.0.1"
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
	session.send_chat(WowSession.CHAT_SAY, ".learn %d" % APPRENTICE)
	session.send_chat(WowSession.CHAT_SAY, ".learn %d" % RECIPE)
	session.send_chat(WowSession.CHAT_SAY, ".additem %d 5" % ROUGH_STONE)
	await _frames(180)

	var found: Array[Dictionary] = TradeSkills.professions()
	var names: PackedStringArray = []
	for profession: Dictionary in found:
		names.append("%s %d/%d" % [profession["name"], profession["rank"], profession["max_rank"]])
	print("professions: ", names)
	var smithing: Dictionary = {}
	for profession: Dictionary in found:
		if profession["skill_line"] == BLACKSMITHING:
			smithing = profession
	_check(not smithing.is_empty(), "the character's professions are read from its skills")
	if smithing.is_empty():
		return _finish("no blacksmithing to work with")

	var recipes: Array[Dictionary] = TradeSkills.recipes(BLACKSMITHING)
	var recipe: Dictionary = {}
	for known: Dictionary in recipes:
		if known["spell"] == RECIPE:
			recipe = known
	_check(not recipe.is_empty(), "and the recipes it knows come out of the skill line")
	if recipe.is_empty():
		print("recipes: ", recipes)
		return _finish("the recipe never resolved")
	print("recipe: ", recipe)
	_check(recipe["product"] == SHARPENING_STONE, "with the item the recipe makes")
	_check(recipe["reagents"].size() == 1, "and the reagents it takes")
	if recipe["reagents"].size() == 1:
		_check(recipe["reagents"][0]["item"] == ROUGH_STONE, "named by entry")

	var stock: Array[Dictionary] = TradeSkills.reagents_held(recipe)
	print("reagents held: ", stock)
	_check(stock[0]["held"] >= stock[0]["need"], "the bags are counted against what it needs")
	_check(TradeSkills.can_make(recipe), "so the recipe can be made")
	_check(
		TradeSkills.difficulty(recipe, smithing["rank"]) == TradeSkills.Difficulty.OPTIMAL,
		"and reads as worth making at this rank",
	)

	var before: int = _count(SHARPENING_STONE)
	TradeSkills.make(recipe)
	var made: bool = await _until(func() -> bool: return _count(SHARPENING_STONE) > before)
	print("sharpening stones: %d before, %d after" % [before, _count(SHARPENING_STONE)])
	_check(made, "and casting it puts the item in the bags")
	_check(session.get_state() == WowSession.STATE_IN_WORLD, "with the session still in the world")
	_finish("")


func _count(entry: int) -> int:
	var held: int = 0
	for bag: int in Inventory.BAG_COUNT + 1:
		for slot: int in Inventory.container_size(bag):
			var item: int = Inventory.container_item(bag, slot)
			if item != 0 and Inventory.entry(item) == entry:
				held += Inventory.stack_count(item)
	return held


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
	print("profession_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
