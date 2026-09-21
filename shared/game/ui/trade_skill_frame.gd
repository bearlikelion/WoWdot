class_name TradeSkillFrame
extends Control

signal close_requested
signal open_requested

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

var _profession: Dictionary = {}
var _recipes: Array[Dictionary] = []
var _selected: int = 0
var _offset: int = 0
# Casts still owed to a Create All, each sent as the one before it lands.
var _queued: int = 0

@onready var _list_scroll: WowScrollFrame = %TradeSkillListScrollFrame
@onready var _create: BaseButton = %TradeSkillCreateButton
@onready var _create_all: BaseButton = %TradeSkillCreateAllButton
@onready var _count: LineEdit = %TradeSkillInputBox


func _ready() -> void:
	for i: int in SKILLS_DISPLAYED:
		_row(i).pressed.connect(_on_row_pressed.bind(i))
	# ponytail: one flat list; the subclass and slot filters wait on recipe subclass data.
	for filter: Control in [
		%TradeSkillInvSlotDropDown, %TradeSkillSubClassDropDown, %TradeSkillExpandButtonFrame,
	]:
		filter.hide()
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
	_recipes = TradeSkills.recipes(_profession["skill_line"])
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
	(%TradeSkillSkillIcon as TextureButton).texture_normal = Inventory.icon(recipe["product"])
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
