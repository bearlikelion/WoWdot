class_name ClassTrainerFrame
extends Control

signal close_requested
signal open_requested

# SMSG_TRAINER_LIST spell states.
enum State { AVAILABLE, UNAVAILABLE, USED }

const CLASS_TRAINER_SKILLS_DISPLAYED: int = 11
const CLASS_TRAINER_SKILL_HEIGHT: float = 16.0
const PLUS_BUTTON: String = "Interface\\Buttons\\UI-PlusButton-Up.blp"
const MINUS_BUTTON: String = "Interface\\Buttons\\UI-MinusButton-Up.blp"
const PLUS_HIGHLIGHT: String = "Interface\\Buttons\\UI-PlusButton-Hilight.blp"
# The default filter: what can be learned now or later, not what is known.
const SHOWN_STATES: Array[State] = [State.AVAILABLE, State.UNAVAILABLE]
const STATE_COLORS: Dictionary[State, Color] = {
	State.AVAILABLE: Color(0.0, 1.0, 0.0),
	State.UNAVAILABLE: Color(0.9, 0.0, 0.0),
	State.USED: Color(0.5, 0.5, 0.5),
}
const SUB_TEXT_COLORS: Dictionary[State, Color] = {
	State.AVAILABLE: Color(0.0, 0.6, 0.0),
	State.UNAVAILABLE: Color(0.6, 0.0, 0.0),
	State.USED: Color(0.5, 0.5, 0.5),
}
const HEADER_COLOR: Color = Color(1.0, 0.82, 0.0)
const RED: Color = Color(1.0, 0.13, 0.13)
const PORTRAIT: PackedScene = preload("res://ui/unit_portrait.tscn")
const PORTRAIT_MASK: Shader = preload("res://ui/portrait.gdshader")

var _guid: int = 0
var _greeting: String = ""
var _services: Array[Dictionary] = []
var _entries: Array[Dictionary] = []
var _collapsed: Dictionary[int, bool] = {}
var _selected: int = 0
var _offset: int = 0
var _textures: Dictionary[String, WowTexture] = {}
var _portrait: UnitPortrait

@onready var _list_scroll: WowScrollFrame = %ClassTrainerListScrollFrame
@onready var _train: BaseButton = %ClassTrainerTrainButton


func _ready() -> void:
	for path: String in [PLUS_BUTTON, MINUS_BUTTON, PLUS_HIGHLIGHT]:
		var texture: WowTexture = WowTexture.new()
		texture.file = path
		_textures[path] = texture
	for i: int in CLASS_TRAINER_SKILLS_DISPLAYED:
		_row(i).pressed.connect(_on_row_pressed.bind(i))
	%ClassTrainerCollapseAllButton.pressed.connect(_on_collapse_all_pressed)
	_train.pressed.connect(_on_train_pressed)
	%ClassTrainerCancelButton.pressed.connect(close_requested.emit)
	%ClassTrainerFrameCloseButton.pressed.connect(close_requested.emit)
	# The filter menu waits on a dropdown port; the stock filter stays on.
	%ClassTrainerFrameFilterDropDown.hide()
	(%ClassTrainerSkillDescription as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(%ClassTrainerSkillRequirements as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(%ClassTrainerGreetingText as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list_scroll.scrolled.connect(_on_list_scrolled)
	_portrait = PORTRAIT.instantiate()
	add_child(_portrait)
	var mask: ShaderMaterial = ShaderMaterial.new()
	mask.shader = PORTRAIT_MASK
	%ClassTrainerFramePortrait.material = mask
	%ClassTrainerFramePortrait.texture = _portrait.get_texture()
	var session: WowSession = WowClient.session
	session.trainer_list_received.connect(_on_list_received)
	session.trainer_spell_bought.connect(_on_spell_bought)
	session.object_updated.connect(_on_object_updated)


func _gui_input(event: InputEvent) -> void:
	var wheel: InputEventMouseButton = event as InputEventMouseButton
	if wheel == null or not wheel.pressed:
		return
	if wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		accept_event()
		var up: bool = wheel.button_index == MOUSE_BUTTON_WHEEL_UP
		var step: float = -CLASS_TRAINER_SKILL_HEIGHT if up else CLASS_TRAINER_SKILL_HEIGHT
		_list_scroll.scroll_to(_list_scroll.scroll() + step)


# ClassTrainerFrame_Update: headers per skill line, then the services the filter lets through.
func refresh() -> void:
	if not is_visible_in_tree():
		return
	var session: WowSession = WowClient.session
	%ClassTrainerNameText.text = session.get_object_name(_guid)
	%ClassTrainerGreetingText.text = _greeting
	(%ClassTrainerMoneyFrame as MoneyFrame).set_money(Inventory.money())
	_build_entries()
	var hidden_entries: int = maxi(_entries.size() - CLASS_TRAINER_SKILLS_DISPLAYED, 0)
	_list_scroll.visible = hidden_entries > 0
	_list_scroll.set_range(hidden_entries * CLASS_TRAINER_SKILL_HEIGHT)
	_offset = mini(_offset, hidden_entries)
	var highlight: Control = %ClassTrainerSkillHighlightFrame
	highlight.hide()
	for i: int in CLASS_TRAINER_SKILLS_DISPLAYED:
		var row: WowButton = _row(i)
		var index: int = i + _offset
		row.visible = index < _entries.size()
		if not row.visible:
			continue
		var entry: Dictionary = _entries[index]
		var text: Label = get_node("%%ClassTrainerSkill%dText" % (i + 1))
		var sub_text: Label = get_node("%%ClassTrainerSkill%dSubText" % (i + 1))
		var normal: TextureRect = row.get_node("NormalTexture")
		var row_highlight: TextureRect = row.get_node("HighlightTexture")
		text.theme_type_variation = &"GameFontHighlight"
		if entry["header"]:
			text.text = entry["name"]
			text.self_modulate = HEADER_COLOR
			sub_text.hide()
			normal.texture = _textures[PLUS_BUTTON if entry["collapsed"] else MINUS_BUTTON]
			row_highlight.texture = _textures[PLUS_HIGHLIGHT]
			row.highlight_locked = false
			continue
		var color: Color = STATE_COLORS[entry["state"]]
		text.text = "  " + entry["name"]
		text.self_modulate = color
		sub_text.visible = not entry["rank"].is_empty()
		sub_text.text = WowStrings.get_text("PARENS_TEMPLATE") % entry["rank"]
		sub_text.theme_type_variation = &"GameFontHighlightSmall"
		sub_text.self_modulate = SUB_TEXT_COLORS[entry["state"]]
		sub_text.position.x = text.position.x + text.get_minimum_size().x + 10.0
		normal.texture = null
		row_highlight.texture = null
		var selected: bool = entry["id"] == _selected
		row.highlight_locked = selected
		if selected:
			highlight.position = row.position
			(%ClassTrainerSkillHighlight as CanvasItem).self_modulate = color
			sub_text.self_modulate = Color.WHITE
			highlight.show()
	var all_collapsed: bool = not _collapsed.is_empty() and _entries.all(
		func(entry: Dictionary) -> bool: return entry["header"]
	)
	var collapse_all: TextureRect = %ClassTrainerCollapseAllButton.get_node("NormalTexture")
	collapse_all.texture = _textures[PLUS_BUTTON if all_collapsed else MINUS_BUTTON]
	_update_details()


func _build_entries() -> void:
	var spells: SpellInfo = WowAssets.spells
	var by_line: Dictionary[int, Array] = {}
	for service: Dictionary in _services:
		if service["state"] not in SHOWN_STATES:
			continue
		var line: int = spells.skill_line(service["taught"])
		if not by_line.has(line):
			by_line[line] = []
		by_line[line].append(service)
	var lines: Array[int] = []
	lines.assign(by_line.keys())
	lines.sort_custom(func(a: int, b: int) -> bool:
		return spells.skill_line_name(a) < spells.skill_line_name(b)
	)
	_entries.clear()
	for line: int in lines:
		var collapsed: bool = _collapsed.has(line)
		var line_name: String = spells.skill_line_name(line)
		_entries.append({
			"header": true, "line": line, "collapsed": collapsed,
			"name": line_name if not line_name.is_empty() else WowStrings.get_text("GENERAL"),
		})
		if not collapsed:
			_entries.append_array(by_line[line])


# ClassTrainer_SetSelection's detail pane: icon, name and rank, what is needed, cost, description.
func _update_details() -> void:
	var service: Dictionary = {}
	for entry: Dictionary in _entries:
		if not entry["header"] and entry["id"] == _selected:
			service = entry
	var detail: CanvasItem = %ClassTrainerDetailScrollFrame
	detail.visible = not service.is_empty()
	_train.disabled = true
	if service.is_empty():
		return
	var spells: SpellInfo = WowAssets.spells
	var taught: int = service["taught"]
	var icon: TextureButton = %ClassTrainerSkillIcon
	icon.texture_normal = spells.icon(taught)
	icon.stretch_mode = TextureButton.STRETCH_SCALE
	%ClassTrainerSkillName.text = service["name"]
	%ClassTrainerSubSkillName.text = WowStrings.get_text("PARENS_TEMPLATE") % service["rank"] \
	if not service["rank"].is_empty() else ""
	var requirements: Label = %ClassTrainerSkillRequirements
	var needs: PackedStringArray = []
	var missing: bool = false
	var session: WowSession = WowClient.session
	var level: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_LEVEL")
	if service["level"] > 1:
		var level_text: String = WowStrings.strip_colors(WowStrings.get_text("TRAINER_REQ_LEVEL"))
		needs.append(level_text % service["level"])
		missing = missing or level < service["level"]
	for prereq: int in service["prereqs"]:
		var known: bool = session.get_known_spells().has(prereq)
		var prereq_name: String = spells.spell_name(prereq)
		var rank: String = spells.rank(prereq)
		needs.append(prereq_name + (" (%s)" % rank if not rank.is_empty() else ""))
		missing = missing or not known
	requirements.visible = not needs.is_empty()
	requirements.text = WowStrings.get_text("REQUIRES_LABEL") + " " + ", ".join(needs)
	requirements.self_modulate = RED if missing else Color.WHITE
	var cost: int = service["cost"]
	(%ClassTrainerCostLabel as CanvasItem).visible = cost > 0
	var money: MoneyFrame = %ClassTrainerDetailMoneyFrame
	money.visible = cost > 0
	money.set_money(cost)
	money.modulate = RED if cost > Inventory.money() else Color.WHITE
	var description: Label = %ClassTrainerSkillDescription
	description.text = SpellText.describe(taught)
	_train.disabled = service["state"] != State.AVAILABLE or cost > Inventory.money() \
	or not service["profession_ok"]
	(%ClassTrainerDetailScrollFrame as WowScrollFrame).refresh()


func _row(index: int) -> WowButton:
	return get_node("%%ClassTrainerSkill%d" % (index + 1))


func _select_first_learnable() -> void:
	_selected = 0
	_build_entries()
	for entry: Dictionary in _entries:
		if not entry["header"]:
			_selected = entry["id"]
			return


func _on_list_received(trainer: Dictionary) -> void:
	var spells: SpellInfo = WowAssets.spells
	var reopened: bool = trainer["guid"] == _guid and is_visible_in_tree()
	_guid = trainer["guid"]
	_greeting = QuestLog.format_text(trainer["greeting"])
	_services.clear()
	for spell: Dictionary in trainer["spells"]:
		var service: Dictionary = spell.duplicate()
		var taught: int = spells.taught_spell(spell["id"])
		service["header"] = false
		service["taught"] = taught
		service["name"] = spells.spell_name(taught)
		service["rank"] = spells.rank(taught)
		_services.append(service)
	if not reopened:
		_offset = 0
		_collapsed.clear()
		_select_first_learnable()
		_portrait.show_unit(_guid)
		open_requested.emit()
	refresh()


# ClassTrainerTrainButton: buying the service asks the trainer for the list again afterwards.
func _on_train_pressed() -> void:
	NpcDialog.send("CMSG_TRAINER_BUY_SPELL", _guid, [_selected])


func _on_spell_bought(_spell: int) -> void:
	NpcDialog.send("CMSG_TRAINER_LIST", _guid)


func _on_row_pressed(index: int) -> void:
	var entry: Dictionary = _entries[index + _offset]
	if entry["header"]:
		if entry["collapsed"]:
			_collapsed.erase(entry["line"])
		else:
			_collapsed[entry["line"]] = true
	else:
		_selected = entry["id"]
	refresh()


func _on_collapse_all_pressed() -> void:
	var headers: Array[Dictionary] = _entries.filter(
		func(entry: Dictionary) -> bool: return entry["header"]
	)
	if _collapsed.is_empty():
		for entry: Dictionary in headers:
			_collapsed[entry["line"]] = true
	else:
		_collapsed.clear()
	refresh()


func _on_list_scrolled(value: float) -> void:
	var offset: int = roundi(value / CLASS_TRAINER_SKILL_HEIGHT)
	if offset != _offset:
		_offset = offset
		refresh()


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid() and is_visible_in_tree():
		refresh()
