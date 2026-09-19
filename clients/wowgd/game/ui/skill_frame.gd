class_name SkillFrame
extends Control

signal close_requested
signal unlearn_requested(skill_id: int, skill_name: String)

const SKILLS_TO_DISPLAY: int = 12
const SKILLFRAME_SKILL_HEIGHT: float = 15.0
const MAX_SKILLS: int = 128
const SKILL_FIELDS: int = 3
# Attributes and Not Displayed never list.
const HIDDEN_CATEGORIES: Array[int] = [5, 12]
# SkillRaceClassInfo flags: the skill can be unlearned, or always reads as 1.
const FLAG_UNLEARNABLE: int = 0x20
const FLAG_MONO_VALUE: int = 0x400
const RANK_GAP: float = 13.0
const PLUS_BUTTON: String = "Interface\\Buttons\\UI-PlusButton-Up.blp"
const MINUS_BUTTON: String = "Interface\\Buttons\\UI-MinusButton-Up.blp"
const SKILL_BAR: Color = Color(0.0, 0.0, 1.0, 0.5)
const SKILL_BACKGROUND: Color = Color(0.0, 0.0, 0.75, 0.5)
const PROFICIENCY_BAR: Color = Color(0.5, 0.5, 0.5)
const PROFICIENCY_BACKGROUND: Color = Color(1.0, 1.0, 1.0, 0.5)

# GetSkillLineInfo rows: category headers, each followed by its skills unless collapsed.
var _entries: Array[Dictionary] = []
var _collapsed: Dictionary[int, bool] = {}
var _selected: int = 0
var _offset: int = 0
var _skill_lines: WowDBC
var _categories: WowDBC
var _skill_flags: Dictionary[int, int] = {}
var _textures: Dictionary[String, WowTexture] = {}

@onready var _list_scroll: WowScrollFrame = %SkillListScrollFrame


func _ready() -> void:
	_skill_lines = WowDBC.open(WowAssets.archive, "SkillLine")
	_categories = WowDBC.open(WowAssets.archive, "SkillLineCategory")
	for path: String in [PLUS_BUTTON, MINUS_BUTTON]:
		var texture: WowTexture = WowTexture.new()
		texture.file = path
		_textures[path] = texture
	for i: int in SKILLS_TO_DISPLAY:
		_label(i).pressed.connect(_on_header_pressed.bind(i))
		(get_node("%%SkillRankFrame%dBorder" % (i + 1)) as BaseButton).pressed.connect(
			_on_skill_pressed.bind(i)
		)
	%SkillFrameCollapseAllButton.pressed.connect(_on_collapse_all_pressed)
	%SkillFrameCancelButton.pressed.connect(close_requested.emit)
	%SkillDetailStatusBarUnlearnButton.pressed.connect(_on_unlearn_pressed)
	(%SkillDetailDescriptionText as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for part: CanvasItem in [
		%SkillDetailStatusBarLeftArrow, %SkillDetailStatusBarRightArrow,
		%SkillDetailStatusBarLearnSkillButton, %SkillDetailCostText,
	]:
		part.hide()
	_list_scroll.scrolled.connect(_on_list_scrolled)
	WowClient.session.object_updated.connect(_on_object_updated)
	visibility_changed.connect(refresh)


func _gui_input(event: InputEvent) -> void:
	var wheel: InputEventMouseButton = event as InputEventMouseButton
	if wheel == null or not wheel.pressed or not _list_rect().has_point(wheel.position):
		return
	if wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		accept_event()
		var up: bool = wheel.button_index == MOUSE_BUTTON_WHEEL_UP
		var step: float = -SKILLFRAME_SKILL_HEIGHT if up else SKILLFRAME_SKILL_HEIGHT
		_list_scroll.scroll_to(_list_scroll.scroll() + step)


# SkillFrame_UpdateSkills.
func refresh() -> void:
	if not is_visible_in_tree():
		return
	_build_entries()
	var hidden_entries: int = maxi(_entries.size() - SKILLS_TO_DISPLAY, 0)
	_list_scroll.visible = hidden_entries > 0
	_list_scroll.set_range(hidden_entries * SKILLFRAME_SKILL_HEIGHT)
	_offset = mini(_offset, hidden_entries)
	for i: int in SKILLS_TO_DISPLAY:
		var index: int = i + _offset
		var bar: TextureProgressBar = _bar(i)
		var label: WowButton = _label(i)
		bar.hide()
		label.hide()
		if index >= _entries.size():
			continue
		var entry: Dictionary = _entries[index]
		if entry["header"]:
			label.show()
			(get_node("%%SkillTypeLabel%dText" % (i + 1)) as Label).text = entry["name"]
			var normal: TextureRect = label.get_node("NormalTexture")
			normal.texture = _textures[PLUS_BUTTON if entry["collapsed"] else MINUS_BUTTON]
		else:
			bar.show()
			_set_bar(bar, "%SkillRankFrame" + str(i + 1), entry)
			var border: WowButton = get_node("%%SkillRankFrame%dBorder" % (i + 1))
			border.highlight_locked = entry["id"] == _selected
	var all_expanded: bool = _collapsed.is_empty()
	var collapse_all: TextureRect = %SkillFrameCollapseAllButton.get_node("NormalTexture")
	collapse_all.texture = _textures[MINUS_BUTTON if all_expanded else PLUS_BUTTON]
	_update_details()


func unlearn(skill_id: int) -> void:
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(4)
	payload.encode_u32(0, skill_id)
	WowClient.session.send_packet("CMSG_UNLEARN_SKILL", payload)


func _build_entries() -> void:
	var by_category: Dictionary[int, Array] = {}
	for skill: Dictionary in _player_skills():
		if not by_category.has(skill["category"]):
			by_category[skill["category"]] = []
		by_category[skill["category"]].append(skill)
	var categories: Array[int] = []
	categories.assign(by_category.keys())
	categories.sort_custom(func(a: int, b: int) -> bool:
		return _categories.get_uint(_categories.find(a), "SortIndex") \
		< _categories.get_uint(_categories.find(b), "SortIndex")
	)
	_entries.clear()
	for category: int in categories:
		var collapsed: bool = _collapsed.has(category)
		_entries.append({
			"header": true, "category": category, "collapsed": collapsed,
			"name": _categories.get_string(_categories.find(category), "Name"),
		})
		if collapsed:
			continue
		var skills: Array = by_category[category]
		skills.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
		for skill: Dictionary in skills:
			_entries.append(skill)


# PLAYER_SKILL_INFO slots: id and step, rank and max rank, then temporary and permanent bonus.
func _player_skills() -> Array[Dictionary]:
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	var first: int = session.field_index("PLAYER_SKILL_INFO_1_1")
	var skills: Array[Dictionary] = []
	for i: int in MAX_SKILLS:
		var id: int = session.get_field(guid, first + i * SKILL_FIELDS) & 0xFFFF
		var row: int = _skill_lines.find(id) if id else -1
		if row < 0:
			continue
		var category: int = _skill_lines.get_uint(row, "Category")
		if category in HIDDEN_CATEGORIES:
			continue
		var ranks: int = session.get_field(guid, first + i * SKILL_FIELDS + 1)
		var bonuses: int = session.get_field(guid, first + i * SKILL_FIELDS + 2)
		skills.append({
			"header": false, "id": id, "category": category, "flags": _flags(id),
			"name": _skill_lines.get_string(row, "Name"),
			"description": _skill_lines.get_string(row, "Description"),
			"rank": ranks & 0xFFFF, "max_rank": ranks >> 16,
			"modifier": _signed_short(bonuses & 0xFFFF) + _signed_short(bonuses >> 16),
		})
	return skills


# SkillFrame_SetStatusBar for the plain skills vanilla has; none are learnable or trainable here.
func _set_bar(bar: TextureProgressBar, prefix: String, skill: Dictionary) -> void:
	var background: ColorRect = get_node(prefix + "Background")
	var rank_text: Label = get_node(prefix + "SkillRank")
	(get_node(prefix + "SkillName") as Label).text = skill["name"]
	(get_node(prefix + "FillBar") as CanvasItem).hide()
	var max_rank: int = skill["max_rank"]
	if max_rank == 1 or skill["flags"] & FLAG_MONO_VALUE:
		bar.max_value = 1.0
		bar.value = 1.0
		bar.tint_progress = PROFICIENCY_BAR
		background.color = PROFICIENCY_BACKGROUND
		rank_text.text = ""
		return
	bar.tint_progress = SKILL_BAR
	background.color = SKILL_BACKGROUND
	bar.max_value = maxi(max_rank, 1)
	bar.value = skill["rank"]
	var modifier: int = skill["modifier"]
	rank_text.text = "%d/%d" % [skill["rank"], max_rank] if modifier == 0 \
	else "%d (%+d)/%d" % [skill["rank"], modifier, max_rank]
	var skill_name: Label = get_node(prefix + "SkillName")
	rank_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rank_text.position.x = skill_name.position.x + skill_name.get_minimum_size().x + RANK_GAP


# SkillDetailFrame_SetStatusBar: nothing shows until a skill is picked.
func _update_details() -> void:
	var skill: Dictionary = {}
	for entry: Dictionary in _entries:
		if not entry["header"] and entry["id"] == _selected:
			skill = entry
	var bar: TextureProgressBar = %SkillDetailStatusBar
	var description: Label = %SkillDetailDescriptionText
	bar.visible = not skill.is_empty()
	description.visible = bar.visible
	if skill.is_empty():
		return
	_set_bar(bar, "%SkillDetailStatusBar", skill)
	%SkillDetailStatusBarUnlearnButton.visible = skill["flags"] & FLAG_UNLEARNABLE != 0
	description.text = WowStrings.strip_colors(WowStrings.get_text("SKILL_DESCRIPTION")) \
	% ["", skill["description"]]
	(%SkillDetailScrollFrame as WowScrollFrame).refresh(true)


# The player's race and class row in SkillRaceClassInfo for a skill.
func _flags(skill: int) -> int:
	if _skill_flags.is_empty():
		var session: WowSession = WowClient.session
		var bytes_0: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_BYTES_0")
		var race_bit: int = 1 << ((bytes_0 & 0xFF) - 1)
		var class_bit: int = 1 << (((bytes_0 >> 8) & 0xFF) - 1)
		var info: WowDBC = WowDBC.open(WowAssets.archive, "SkillRaceClassInfo")
		for row: int in info.row_count():
			if info.get_uint(row, "RaceMask") & race_bit and info.get_uint(row, "ClassMask") & class_bit:
				_skill_flags[info.get_uint(row, "SkillID")] = info.get_uint(row, "Flags")
	return _skill_flags.get(skill, 0)


func _signed_short(value: int) -> int:
	return value - 0x10000 if value >= 0x8000 else value


func _list_rect() -> Rect2:
	var first: Control = _label(0)
	return Rect2(first.position, Vector2(first.size.x, SKILLFRAME_SKILL_HEIGHT * SKILLS_TO_DISPLAY))


func _bar(index: int) -> TextureProgressBar:
	return get_node("%%SkillRankFrame%d" % (index + 1))


func _label(index: int) -> WowButton:
	return get_node("%%SkillTypeLabel%d" % (index + 1))


func _on_header_pressed(index: int) -> void:
	var category: int = _entries[index + _offset]["category"]
	if _collapsed.has(category):
		_collapsed.erase(category)
	else:
		_collapsed[category] = true
	refresh()


func _on_skill_pressed(index: int) -> void:
	_selected = _entries[index + _offset]["id"]
	refresh()


func _on_collapse_all_pressed() -> void:
	if _collapsed.is_empty():
		for entry: Dictionary in _entries:
			if entry["header"]:
				_collapsed[entry["category"]] = true
		_list_scroll.scroll_to(0.0)
	else:
		_collapsed.clear()
	refresh()


func _on_unlearn_pressed() -> void:
	for entry: Dictionary in _entries:
		if not entry["header"] and entry["id"] == _selected:
			unlearn_requested.emit(_selected, entry["name"])


func _on_list_scrolled(value: float) -> void:
	var offset: int = roundi(value / SKILLFRAME_SKILL_HEIGHT)
	if offset != _offset:
		_offset = offset
		refresh()


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid():
		refresh()
