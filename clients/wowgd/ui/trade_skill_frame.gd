class_name TradeSkillFrame
extends Control

signal close_requested
signal open_requested
signal filter_menu_requested(entries: Array[Dictionary], chosen: Callable)

const SKILLS_DISPLAYED: int = 8
const SKILL_HEIGHT: float = 16.0
const MAX_REAGENTS: int = 8
# TradeSkillTypeColor in the stock Lua.
const DIFFICULTY_COLORS: Dictionary[TradeSkills.Difficulty, Color] = {
	TradeSkills.Difficulty.OPTIMAL: Color(1.0, 0.5, 0.25),
	TradeSkills.Difficulty.MEDIUM: Color(1.0, 1.0, 0.0),
	TradeSkills.Difficulty.EASY: Color(0.25, 0.75, 0.25),
	TradeSkills.Difficulty.TRIVIAL: Color(0.5, 0.5, 0.5),
}
const LACKING_COLOR: Color = Color(0.5, 0.5, 0.5)
const FILTER_WIDTH: float = 120.0
# The subclass filter overlaps the slot filter's left cap by this much.
const FILTER_OVERLAP: float = 35.0

var _profession: Dictionary = {}
var _recipes: Array[Dictionary] = []
var _selected: int = 0
var _offset: int = 0
# Casts still owed to a Create All, each sent as the one before it lands.
var _queued: int = 0
# The chosen filter menu ids; 0 shows everything, a subclass is (class << 8 | subclass) + 1.
var _subclass_filter: int = 0
var _slot_filter: int = 0

@onready var _list_scroll: WowScrollFrame = %TradeSkillListScrollFrame
@onready var _create: BaseButton = %TradeSkillCreateButton
@onready var _create_all: BaseButton = %TradeSkillCreateAllButton
@onready var _count: LineEdit = %TradeSkillInputBox


func _ready() -> void:
	for i: int in SKILLS_DISPLAYED:
		_row(i).pressed.connect(_on_row_pressed.bind(i))
	# ponytail: one flat list without the stock category headers.
	%TradeSkillExpandButtonFrame.hide()
	var slot_filter: Control = %TradeSkillInvSlotDropDown
	var subclass_filter: Control = %TradeSkillSubClassDropDown
	DropDownList.set_width(slot_filter, FILTER_WIDTH)
	subclass_filter.offset_right = slot_filter.offset_left + FILTER_OVERLAP
	DropDownList.set_width(subclass_filter, FILTER_WIDTH)
	%TradeSkillSubClassDropDownButton.pressed.connect(_open_subclass_menu)
	%TradeSkillInvSlotDropDownButton.pressed.connect(_open_slot_menu)
	_create.pressed.connect(func() -> void: _make(_typed_count()))
	_create_all.pressed.connect(func() -> void: _make(_makeable(_recipe())))
	%TradeSkillCancelButton.pressed.connect(close_requested.emit)
	%TradeSkillFrameCloseButton.pressed.connect(close_requested.emit)
	%TradeSkillIncrementButton.pressed.connect(_step_count.bind(1))
	%TradeSkillDecrementButton.pressed.connect(_step_count.bind(-1))
	_list_scroll.scrolled.connect(_on_list_scrolled)
	var product: TextureButton = %TradeSkillSkillIcon
	product.ignore_texture_size = true
	product.stretch_mode = TextureButton.STRETCH_SCALE
	_count.text = "1"
	var session: WowSession = WowClient.session
	session.spell_cast_finished.connect(_on_cast_finished)
	session.spell_cast_failed.connect(_on_cast_failed)
	session.object_updated.connect(_on_object_updated)
	session.item_info_received.connect(_on_object_updated)


func set_portrait(texture: Texture2D) -> void:
	(%TradeSkillFramePortrait as TextureRect).texture = texture


# TradeSkillFrame_Show for the profession a cast spell belongs to; false when it is none.
func open_for_spell(spell_id: int) -> bool:
	var line: int = WowAssets.spells.skill_line(spell_id)
	for profession: Dictionary in TradeSkills.professions():
		if profession["skill_line"] != line:
			continue
		_profession = profession
		_selected = 0
		_offset = 0
		_queued = 0
		_subclass_filter = 0
		_slot_filter = 0
		open_requested.emit()
		refresh()
		return true
	return false


func refresh() -> void:
	if not is_visible_in_tree() or _profession.is_empty():
		return
	for profession: Dictionary in TradeSkills.professions():
		if profession["skill_line"] == _profession["skill_line"]:
			_profession = profession
	_recipes.assign(TradeSkills.recipes(_profession["skill_line"]).filter(_passes_filters))
	%TradeSkillSubClassDropDownText.text = _filter_text(_subclass_filter, "ALL_SUBCLASSES")
	%TradeSkillInvSlotDropDownText.text = _filter_text(_slot_filter, "ALL_INVENTORY_SLOTS")
	if _recipe().is_empty() and not _recipes.is_empty():
		_selected = _recipes[0]["spell"]
	%TradeSkillFrameTitleText.text = _profession["name"]
	# The title already names the profession, and at this width the two texts collide.
	%TradeSkillRankFrameSkillName.text = ""
	%TradeSkillRankFrameSkillRank.text = "%d/%d" % [_profession["rank"], _profession["max_rank"]]
	var rank_bar: Range = %TradeSkillRankFrame as Range
	if rank_bar:
		rank_bar.max_value = _profession["max_rank"]
		rank_bar.value = _profession["rank"]
	var hidden_rows: int = maxi(_recipes.size() - SKILLS_DISPLAYED, 0)
	_list_scroll.visible = hidden_rows > 0
	_list_scroll.set_range(hidden_rows * SKILL_HEIGHT)
	_offset = mini(_offset, hidden_rows)
	var highlight: Control = %TradeSkillHighlightFrame
	highlight.hide()
	for i: int in SKILLS_DISPLAYED:
		var row: WowButton = _row(i)
		var index: int = i + _offset
		row.visible = index < _recipes.size()
		if not row.visible:
			continue
		var recipe: Dictionary = _recipes[index]
		var color: Color = DIFFICULTY_COLORS[TradeSkills.difficulty(recipe, _profession["rank"])]
		var makeable: int = _makeable(recipe)
		var text: Label = get_node("%%TradeSkillSkill%dText" % (i + 1))
		text.text = " %s [%d]" % [recipe["name"], makeable] if makeable > 0 \
		else " " + recipe["name"]
		text.self_modulate = color
		(get_node("%%TradeSkillSkill%dSubText" % (i + 1)) as Label).hide()
		(row.get_node("NormalTexture") as TextureRect).texture = null
		var selected: bool = recipe["spell"] == _selected
		row.highlight_locked = selected
		if selected:
			highlight.position = row.position
			(%TradeSkillHighlight as CanvasItem).self_modulate = color
			highlight.show()
	_update_details()


# SetTradeSkillSubClassFilter and SetTradeSkillInvSlotFilter, keyed by the product item.
func _passes_filters(recipe: Dictionary) -> bool:
	var info: Dictionary = WowClient.session.get_item_info(recipe["product"]) \
			if recipe["product"] else {}
	if _subclass_filter and (info.is_empty() or _subclass_id(info) != _subclass_filter):
		return false
	return not _slot_filter or (not info.is_empty() and _slot(info) == _slot_filter)


# Robes go in the chest slot, so they file under Chest with the rest.
func _slot(info: Dictionary) -> int:
	const INVTYPE_CHEST: int = 5
	const INVTYPE_ROBE: int = 20
	var slot: int = info["inventory_type"]
	return INVTYPE_CHEST if slot == INVTYPE_ROBE else slot


func _subclass_id(info: Dictionary) -> int:
	return (info["class"] << 8 | info["subclass"]) + 1


func _filter_text(id: int, all_key: String) -> String:
	for entry: Dictionary in _filter_entries(all_key):
		if entry["id"] == id:
			return entry["text"]
	return WowStrings.get_text(all_key)


# The subclasses or slots this profession's products come in, after the "All" entry.
func _filter_entries(all_key: String) -> Array[Dictionary]:
	var found: Dictionary[int, String] = {}
	for recipe: Dictionary in TradeSkills.recipes(_profession["skill_line"]):
		var info: Dictionary = WowClient.session.get_item_info(recipe["product"]) \
				if recipe["product"] else {}
		if info.is_empty():
			continue
		if all_key == "ALL_SUBCLASSES":
			found[_subclass_id(info)] = WowClient.proficiencies.subclass_name(
				info["class"], info["subclass"]
			)
		elif _slot(info) < GameTooltip.INVENTORY_TYPES.size() \
		and not GameTooltip.INVENTORY_TYPES[_slot(info)].is_empty():
			found[_slot(info)] = WowStrings.get_text(GameTooltip.INVENTORY_TYPES[_slot(info)])
	var entries: Array[Dictionary] = [{"text": WowStrings.get_text(all_key), "id": 0}]
	for id: int in found:
		entries.append({"text": found[id], "id": id})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["id"] == 0 or (b["id"] != 0 and a["text"] < b["text"])
	)
	return entries


func _open_subclass_menu() -> void:
	filter_menu_requested.emit(_filter_entries("ALL_SUBCLASSES"), func(id: int) -> void:
		_subclass_filter = id
		_offset = 0
		refresh()
	)


func _open_slot_menu() -> void:
	filter_menu_requested.emit(_filter_entries("ALL_INVENTORY_SLOTS"), func(id: int) -> void:
		_slot_filter = id
		_offset = 0
		refresh()
	)


func _update_details() -> void:
	var recipe: Dictionary = _recipe()
	var detail: Control = %TradeSkillDetailScrollChildFrame
	detail.visible = not recipe.is_empty()
	_create.disabled = recipe.is_empty() or not TradeSkills.can_make(recipe)
	_create_all.disabled = _create.disabled
	if recipe.is_empty():
		return
	%TradeSkillSkillName.text = recipe["name"]
	%TradeSkillRequirementLabel.hide()
	%TradeSkillRequirementText.hide()
	%TradeSkillSkillCooldown.hide()
	# ponytail: stock gives enchanting its own CraftFrame; here its recipes share this window.
	(%TradeSkillSkillIcon as TextureButton).texture_normal = Inventory.icon(recipe["product"]) \
	if recipe["product"] != 0 else WowAssets.spells.icon(recipe["spell"])
	var made: Label = %TradeSkillSkillIconCount
	made.visible = recipe["made"] > 1
	made.text = str(recipe["made"])
	var stock: Array[Dictionary] = TradeSkills.reagents_held(recipe)
	for i: int in MAX_REAGENTS:
		var slot: Control = get_node("%%TradeSkillReagent%d" % (i + 1))
		slot.visible = i < stock.size()
		if not slot.visible:
			continue
		var reagent: Dictionary = stock[i]
		var info: Dictionary = WowClient.session.get_item_info(reagent["item"])
		var name_label: Label = get_node("%%TradeSkillReagent%dName" % (i + 1))
		name_label.text = info.get("name", "")
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var enough: bool = reagent["held"] >= reagent["need"]
		name_label.self_modulate = Color.WHITE if enough else LACKING_COLOR
		var icon: TextureRect = get_node("%%TradeSkillReagent%dIconTexture" % (i + 1))
		icon.texture = Inventory.icon(reagent["item"])
		icon.self_modulate = Color.WHITE if enough else LACKING_COLOR
		(get_node("%%TradeSkillReagent%dCount" % (i + 1)) as Label).text = "%d/%d" % [
			reagent["held"], reagent["need"],
		]


func _recipe() -> Dictionary:
	for recipe: Dictionary in _recipes:
		if recipe["spell"] == _selected:
			return recipe
	return {}


# How many times the bags' reagents cover the recipe.
func _makeable(recipe: Dictionary) -> int:
	if recipe.is_empty():
		return 0
	var times: int = -1
	for reagent: Dictionary in TradeSkills.reagents_held(recipe):
		var covers: int = reagent["held"] / maxi(reagent["need"], 1)
		times = covers if times < 0 else mini(times, covers)
	return maxi(times, 0)


func _typed_count() -> int:
	return clampi(_count.text.to_int(), 1, maxi(_makeable(_recipe()), 1))


func _step_count(step: int) -> void:
	_count.text = str(clampi(_count.text.to_int() + step, 1, maxi(_makeable(_recipe()), 1)))


func _make(times: int) -> void:
	var recipe: Dictionary = _recipe()
	if recipe.is_empty() or times <= 0:
		return
	_queued = times - 1
	TradeSkills.make(recipe)


func _row(index: int) -> WowButton:
	return get_node("%%TradeSkillSkill%d" % (index + 1))


func _on_row_pressed(index: int) -> void:
	_selected = _recipes[index + _offset]["spell"]
	_count.text = "1"
	refresh()


func _on_list_scrolled(value: float) -> void:
	var offset: int = roundi(value / SKILL_HEIGHT)
	if offset != _offset:
		_offset = offset
		refresh()


func _on_cast_finished(caster: int, spell_id: int, _targets: PackedInt64Array) -> void:
	if caster != WowClient.session.get_player_guid() or spell_id != _selected:
		return
	if _queued > 0 and is_visible_in_tree():
		_queued -= 1
		TradeSkills.make.call_deferred(_recipe())
	refresh.call_deferred()


func _on_cast_failed(caster: int, _spell_id: int, _reason: int) -> void:
	if caster == WowClient.session.get_player_guid():
		_queued = 0


# Bag contents and the skill rank both arrive as updates to the player or their items.
func _on_object_updated(_guid: int) -> void:
	if is_visible_in_tree():
		refresh.call_deferred()
