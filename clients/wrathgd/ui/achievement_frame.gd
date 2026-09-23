class_name AchievementFrame
extends Control

signal close_requested

# The fake first entry of the category list that shows the summary page.
const SUMMARY: int = -1
const STATISTICS_CATEGORY: int = 1
const COUNTER_FLAG: int = 0x1
const HORDE_FACTION: int = 0
const ALLIANCE_FACTION: int = 1
const CATEGORY_BUTTONS: int = 20
const ACHIEVEMENT_BUTTONS: int = 7
const SUMMARY_BUTTONS: int = 4
const COLLAPSED_HEIGHT: float = 84.0
const BUTTON_GAP: float = 2.0
const CATEGORIES_WIDTH: float = 175.0
const FEAT_OF_STRENGTH: int = 81
# The summary page's progress bars, by the category id each XML bar carries.
const SUMMARY_CATEGORIES: Array[int] = [92, 96, 97, 95, 168, 169, 201, 155]
const CHILD_TINT: Color = Color(0.6, 0.6, 0.6)
const DATE_OFFSET: Vector2 = Vector2(-3.0, -6.0)
const DIM_TEXT: Color = Color(0.65, 0.65, 0.65)
const PARCHMENT: String = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal.blp"
const PARCHMENT_DESATURATED: String = \
		"Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal-Desaturated.blp"
const DESATURATE: Shader = preload("res://ui/desaturate.gdshader")

# Achievement categories as {id, parent, name, order}, statistics left out.
var _categories: Array[Dictionary] = []
# Each category id to its achievements as {id, title, description, points, icon, reward, ...}.
var _by_category: Dictionary[int, Array] = {}
var _selected: int = SUMMARY
var _expanded: int = 0
var _entries: Array[Dictionary] = []
var _list: Array[Dictionary] = []
var _category_offset: int = 0
var _achievement_offset: int = 0
var _desaturate: ShaderMaterial = ShaderMaterial.new()

@onready var _achievements: Achievements = WowClient.achievements
@onready var _category_scroll: WowScrollFrame = %AchievementFrameCategoriesContainer
@onready var _achievement_scroll: WowScrollFrame = %AchievementFrameAchievementsContainer


func _ready() -> void:
	_desaturate.shader = DESATURATE
	for i: int in CATEGORY_BUTTONS:
		_category_button(i).pressed.connect(_on_category_pressed.bind(i))
	for i: int in ACHIEVEMENT_BUTTONS:
		var button: Control = _achievement_button(i)
		button.position.y = i * (COLLAPSED_HEIGHT + BUTTON_GAP)
		button.size.y = COLLAPSED_HEIGHT
	_category_scroll.faux = true
	_category_scroll.scrolled.connect(_on_categories_scrolled)
	_achievement_scroll.faux = true
	_achievement_scroll.scrolled.connect(_on_achievements_scrolled)
	%AchievementFrameCloseButton.pressed.connect(close_requested.emit)
	%AchievementFrameTab2.hide()
	%AchievementFrameFilterDropDown.hide()
	(%AchievementFrameTab1Text as Label).text = WowStrings.get_text("ACHIEVEMENTS")
	_achievements.changed.connect(refresh)
	visibility_changed.connect(refresh)


func refresh() -> void:
	if not is_visible_in_tree():
		return
	if _categories.is_empty():
		_load()
	%AchievementFrameHeaderPoints.text = str(_achievements.points())
	_list_categories()
	_category_scroll.set_range(maxi(_entries.size() - CATEGORY_BUTTONS, 0))
	_show_categories()
	var summary: bool = _selected == SUMMARY
	%AchievementFrameSummary.visible = summary
	%AchievementFrameAchievements.visible = not summary
	if summary:
		_show_summary()
	else:
		_list = _category_list(_selected)
		%AchievementFrameAchievementsFeatOfStrengthText.visible = \
				_selected == FEAT_OF_STRENGTH and _list.is_empty()
		_achievement_scroll.set_range(maxi(_list.size() - _achievements_shown(), 0))
		_show_achievements()


func _load() -> void:
	var guid: int = WowClient.session.get_player_guid()
	var race: int = WowClient.session.get_field(guid, "UNIT_FIELD_BYTES_0") & 0xFF
	var faction: int = HORDE_FACTION if race in [2, 5, 6, 8, 10] else ALLIANCE_FACTION
	var table: WowDBC = WowDBC.open(WowAssets.archive, "Achievement_Category")
	var parents: Dictionary[int, int] = {}
	for row: int in table.row_count():
		parents[table.get_uint(row, "ID")] = table.get_int(row, "Parent")
	for row: int in table.row_count():
		var id: int = table.get_uint(row, "ID")
		if id == STATISTICS_CATEGORY or parents[id] == STATISTICS_CATEGORY \
		or parents.get(parents[id], 0) == STATISTICS_CATEGORY:
			continue
		_categories.append({
			"id": id, "parent": parents[id], "name": table.get_string(row, "Name"),
			"order": table.get_uint(row, "UIOrder"),
		})
		_by_category[id] = []
	_categories.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"]
	)
	var achievements: WowDBC = WowDBC.open(WowAssets.archive, "Achievement")
	for row: int in achievements.row_count():
		var category: int = achievements.get_uint(row, "CategoryID")
		var side: int = achievements.get_int(row, "Faction")
		if not _by_category.has(category) or achievements.get_uint(row, "Flags") & COUNTER_FLAG \
		or (side != -1 and side != faction):
			continue
		_by_category[category].append({
			"id": achievements.get_uint(row, "ID"),
			"title": achievements.get_string(row, "Title"),
			"description": achievements.get_string(row, "Description"),
			"points": achievements.get_uint(row, "Points"),
			"icon": achievements.get_uint(row, "IconID"),
			"reward": achievements.get_string(row, "Reward"),
			"supercedes": achievements.get_uint(row, "Supercedes"),
			"order": achievements.get_uint(row, "UIOrder"),
		})


# A series shows only its next step: the last one done, or the first one not yet done.
func _category_list(category: int) -> Array[Dictionary]:
	var all: Array = _by_category.get(category, [])
	var next_done: Dictionary[int, bool] = {}
	for entry: Dictionary in all:
		if entry["supercedes"] and _achievements.completed.has(entry["id"]):
			next_done[entry["supercedes"]] = true
	var shown: Array[Dictionary] = []
	for entry: Dictionary in all:
		var previous: int = entry["supercedes"]
		if previous and not _achievements.completed.has(previous):
			continue
		if next_done.has(entry["id"]):
			continue
		shown.append(entry)
	shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_done: bool = _achievements.completed.has(a["id"])
		if a_done != _achievements.completed.has(b["id"]):
			return a_done
		return a["order"] < b["order"])
	return shown


func _list_categories() -> void:
	var summary_name: String = WowStrings.get_text("ACHIEVEMENT_SUMMARY_CATEGORY")
	_entries = [{"id": SUMMARY, "parent": -1, "name": summary_name}]
	for category: Dictionary in _categories:
		if category["parent"] == -1:
			_entries.append(category)
			if category["id"] == _expanded:
				for child: Dictionary in _categories:
					if child["parent"] == _expanded:
						_entries.append(child)


func _show_categories() -> void:
	for i: int in CATEGORY_BUTTONS:
		var button: WowButton = _category_button(i)
		var index: int = _category_offset + i
		button.visible = index < _entries.size()
		if not button.visible:
			continue
		var entry: Dictionary = _entries[index]
		var child: bool = entry["parent"] != -1
		button.size.x = CATEGORIES_WIDTH - (25.0 if child else 10.0)
		button.position.x = 15.0 if child else 0.0
		var prefix: String = "%%AchievementFrameCategoriesContainerButton%d" % (i + 1)
		var label: Label = get_node(prefix + "Label")
		label.text = entry["name"]
		label.theme_type_variation = &"GameFontHighlight" if child else &"GameFontNormal"
		(get_node(prefix + "Background") as CanvasItem).self_modulate = \
				CHILD_TINT if child else Color.WHITE
		button.highlight_locked = entry["id"] == _selected


func _achievements_shown() -> int:
	return floori(_achievement_scroll.size.y / (COLLAPSED_HEIGHT + BUTTON_GAP))


func _show_achievements() -> void:
	for i: int in ACHIEVEMENT_BUTTONS:
		var index: int = _achievement_offset + i
		var button: Control = _achievement_button(i)
		button.visible = index < _list.size()
		if button.visible:
			var prefix: String = "%%AchievementFrameAchievementsContainerButton%d" % (i + 1)
			_show_achievement(prefix, _list[index])


# AchievementButton_DisplayAchievement, collapsed: the criteria stay hidden.
func _show_achievement(prefix: String, entry: Dictionary) -> void:
	var done: bool = _achievements.completed.has(entry["id"])
	(get_node(prefix + "Label") as Label).text = entry["title"]
	(get_node(prefix + "Label") as CanvasItem).self_modulate = Color.WHITE if done else DIM_TEXT
	var description: Label = get_node(prefix + "Description")
	description.text = entry["description"]
	description.self_modulate = Color.BLACK if done else Color.WHITE
	var points: Label = get_node(prefix + "ShieldPoints")
	points.text = str(entry["points"]) if entry["points"] else ""
	var icon: TextureRect = get_node(prefix + "IconTexture")
	icon.texture = WowAssets.spells.icon_texture(WowAssets.spells.icon_path(entry["icon"]))
	icon.material = null if done else _desaturate
	(get_node(prefix + "ShieldIcon") as CanvasItem).material = null if done else _desaturate
	var background: TextureRect = get_node_or_null(prefix + "Background")
	if background:
		var parchment: WowTexture = WowTexture.new()
		parchment.file = PARCHMENT if done else PARCHMENT_DESATURATED
		background.texture = parchment
	var date: Label = get_node(prefix + "DateCompleted")
	date.visible = done
	if done:
		var when: Dictionary = Achievements.unpack_date(_achievements.completed[entry["id"]])
		date.text = WowStrings.format(
			WowStrings.get_text("SHORTDATE"), [when["day"], when["month"], when["year"] % 100]
		)
		# AchievementButton_OnLoad hangs the date under the shield.
		var shield: Control = get_node(prefix + "Shield")
		date.position = shield.position + Vector2(
			(shield.size.x - date.size.x) / 2.0 + DATE_OFFSET.x, shield.size.y + DATE_OFFSET.y
		)
	var reward: Label = get_node_or_null(prefix + "Reward")
	if reward:
		reward.visible = not entry["reward"].is_empty()
		reward.text = entry["reward"]
		(get_node(prefix + "RewardBackground") as CanvasItem).visible = reward.visible
	for part: String in ["HiddenDescription", "Check", "PlusMinus", "Tracked", "Objectives"]:
		var node: CanvasItem = get_node_or_null(prefix + part)
		if node:
			node.hide()


# AchievementFrameSummary_Update: the overall bar, the category bars and the latest four done.
func _show_summary() -> void:
	var total: Array[int] = _count(_categories.map(func(c: Dictionary) -> int: return c["id"]))
	var bar: Range = %AchievementFrameSummaryCategoriesStatusBar
	bar.max_value = maxi(total[0], 1)
	bar.value = total[1]
	%AchievementFrameSummaryCategoriesStatusBarText.text = "%d/%d" % [total[1], total[0]]
	for i: int in SUMMARY_CATEGORIES.size():
		var id: int = SUMMARY_CATEGORIES[i]
		var ids: Array = [id]
		for category: Dictionary in _categories:
			if category["parent"] == id:
				ids.append(category["id"])
		var counts: Array[int] = _count(ids)
		var prefix: String = "%%AchievementFrameSummaryCategoriesCategory%d" % (i + 1)
		var category_bar: Range = get_node(prefix)
		category_bar.max_value = maxi(counts[0], 1)
		category_bar.value = counts[1]
		(get_node(prefix + "Text") as Label).text = "%d/%d" % [counts[1], counts[0]]
		for category: Dictionary in _categories:
			if category["id"] == id:
				(get_node(prefix + "Label") as Label).text = category["name"]
	var latest: Array[Dictionary] = []
	for list: Array in _by_category.values():
		for entry: Dictionary in list:
			if _achievements.completed.has(entry["id"]):
				latest.append(entry)
	latest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _achievements.completed[a["id"]] > _achievements.completed[b["id"]])
	%AchievementFrameSummaryAchievementsEmptyText.visible = latest.is_empty()
	for i: int in SUMMARY_BUTTONS:
		var button: Control = get_node("%%AchievementFrameSummaryAchievement%d" % (i + 1))
		button.visible = i < latest.size()
		if button.visible:
			_show_achievement("%%AchievementFrameSummaryAchievement%d" % (i + 1), latest[i])


# Total and completed achievements across the given categories.
func _count(ids: Array) -> Array[int]:
	var counts: Array[int] = [0, 0]
	for id: int in ids:
		for entry: Dictionary in _by_category.get(id, []):
			counts[0] += 1
			if _achievements.completed.has(entry["id"]):
				counts[1] += 1
	return counts


func _category_button(index: int) -> WowButton:
	return get_node("%%AchievementFrameCategoriesContainerButton%d" % (index + 1))


func _achievement_button(index: int) -> Control:
	return get_node("%%AchievementFrameAchievementsContainerButton%d" % (index + 1))


func _on_category_pressed(index: int) -> void:
	var entry: Dictionary = _entries[_category_offset + index]
	_selected = entry["id"]
	if entry["parent"] == -1:
		_expanded = 0 if _expanded == _selected else _selected
	_achievement_offset = 0
	refresh()


func _on_categories_scrolled(value: float) -> void:
	_category_offset = roundi(value)
	_show_categories()


func _on_achievements_scrolled(value: float) -> void:
	_achievement_offset = roundi(value)
	_show_achievements()
