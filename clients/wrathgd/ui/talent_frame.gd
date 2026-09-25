class_name TalentFrame
extends Control

signal close_requested

enum Branch { NONE, MET, UNMET }
enum Spec { PRIMARY, SECONDARY, PET }

const MAX_TALENT_TABS: int = 3
const MAX_NUM_TALENTS: int = 40
const MAX_NUM_TALENT_TIERS: int = 15
const NUM_TALENT_COLUMNS: int = 4
const MAX_NUM_BRANCH_TEXTURES: int = 30
const MAX_NUM_ARROW_TEXTURES: int = 30
const MAX_RANKS: int = 9
const MAX_PREREQS: int = 3
const POINTS_PER_TIER: int = 5
const TALENT_BUTTON_SIZE: float = 32.0
const TALENT_SPACING: float = 63.0
const INITIAL_TALENT_OFFSET: Vector2 = Vector2(35.0, 20.0)
const TAB_PADDING: float = 10.0
const BACKGROUND: String = "Interface\\TalentFrame\\%s-%s.blp"
const BACKGROUND_PIECES: PackedStringArray = ["TopLeft", "TopRight", "BottomLeft", "BottomRight"]
const GREEN_FONT_COLOR: Color = Color(0.1, 1.0, 0.1)
const NORMAL_FONT_COLOR: Color = Color(1.0, 0.82, 0.0)
const GRAY_FONT_COLOR: Color = Color(0.5, 0.5, 0.5)
const DESATURATED_TINT: Color = Color(0.65, 0.65, 0.65)
# TALENT_ACTIVATION_SPELLS: Activate Primary Spec and Activate Secondary Spec.
const ACTIVATE_SPELLS: Array[int] = [63645, 63644]
const HYBRID_ICON: String = "Interface\\Icons\\Ability_DualWieldSpecialization"
const DEFAULT_SPEC_ICON: String = "Interface\\Icons\\Ability_Marksmanship"
# PlayerTalentFrame_UpdateSpecs: the first spec tab's top, and the gaps below each tab.
const SPEC_TAB_TOP: float = 65.0
const SPEC_TAB_GAP: float = 22.0
const PET_SPEC_TAB_GAP: float = 39.0
# SetTexCoord's left, right, top, bottom for a lit piece, then a gray one; left past right mirrors.
const BRANCH_COORDS: Dictionary[String, Array] = {
	"up": [[0.12890625, 0.25390625, 0.0, 0.484375], [0.12890625, 0.25390625, 0.515625, 1.0]],
	"down": [[0.0, 0.125, 0.0, 0.484375], [0.0, 0.125, 0.515625, 1.0]],
	"left": [[0.2578125, 0.3828125, 0.0, 0.5], [0.2578125, 0.3828125, 0.5, 1.0]],
	"right": [[0.2578125, 0.3828125, 0.0, 0.5], [0.2578125, 0.3828125, 0.5, 1.0]],
	"topright": [[0.515625, 0.640625, 0.0, 0.5], [0.515625, 0.640625, 0.5, 1.0]],
	"topleft": [[0.640625, 0.515625, 0.0, 0.5], [0.640625, 0.515625, 0.5, 1.0]],
	"bottomright": [[0.38671875, 0.51171875, 0.0, 0.5], [0.38671875, 0.51171875, 0.5, 1.0]],
	"bottomleft": [[0.51171875, 0.38671875, 0.0, 0.5], [0.51171875, 0.38671875, 0.5, 1.0]],
	"tdown": [[0.64453125, 0.76953125, 0.0, 0.5], [0.64453125, 0.76953125, 0.5, 1.0]],
	"tup": [[0.7734375, 0.8984375, 0.0, 0.5], [0.7734375, 0.8984375, 0.5, 1.0]],
}
const ARROW_COORDS: Dictionary[String, Array] = {
	"top": [[0.0, 0.5, 0.0, 0.5], [0.0, 0.5, 0.5, 1.0]],
	"right": [[1.0, 0.5, 0.0, 0.5], [1.0, 0.5, 0.5, 1.0]],
	"left": [[0.5, 1.0, 0.0, 0.5], [0.5, 1.0, 0.5, 1.0]],
}
const PORTRAIT: PackedScene = preload("res://ui/unit_portrait.tscn")
const PORTRAIT_MASK: Shader = preload("res://ui/portrait.gdshader")
const DESATURATE: Shader = preload("res://ui/desaturate.gdshader")

var _talents: WowDBC
var _talent_tabs: WowDBC
var _tab_rows: Dictionary[int, Array] = {}
var _tabs: Array[int] = []
var _tab: int = 0
var _shown: Array[int] = []
var _branches: Array[Array] = []
var _branch_index: int = 0
var _arrow_index: int = 0
var _points: int = 0
var _points_spent: int = 0
var _known: Dictionary[int, bool] = {}
var _tab_gap: float = 0.0
var _desaturate: ShaderMaterial = ShaderMaterial.new()
var _portrait: UnitPortrait
var _spec: Spec = Spec.PRIMARY
var _families: WowDBC

@onready var _scroll: WowScrollFrame = _part("ScrollFrame")


func _ready() -> void:
	_setup()
	# Talent previews are not ported.
	_part("PreviewBar").hide()
	_families = WowDBC.open(WowAssets.archive, "CreatureFamily")
	for spec: Spec in [Spec.PRIMARY, Spec.SECONDARY, Spec.PET]:
		_spec_tab(spec).pressed.connect(_select_spec.bind(spec))
	(_part("ActivateButtonText") as Label).text = WowStrings.get_text("TALENT_SPEC_ACTIVATE")
	(_part("ActivateButton") as BaseButton).pressed.connect(
		func() -> void: WowClient.session.cast_spell(ACTIVATE_SPELLS[_spec], 0)
	)
	(_part("Tab4") as BaseButton).pressed.connect(show_glyphs)
	%GlyphFrame.hide()
	WowClient.session.spells_changed.connect(refresh)
	WowClient.talents.changed.connect(refresh)
	WowClient.pet.changed.connect(refresh)


# What the player's and an inspected unit's trees share.
func _setup() -> void:
	_talents = WowDBC.open(WowAssets.archive, "Talent")
	_talent_tabs = WowDBC.open(WowAssets.archive, "TalentTab")
	_desaturate.shader = DESATURATE
	for tier: int in MAX_NUM_TALENT_TIERS:
		var row: Array[BranchNode] = []
		for column: int in NUM_TALENT_COLUMNS:
			row.append(BranchNode.new())
		_branches.append(row)
	for i: int in MAX_NUM_TALENTS:
		var button: ItemButton = _button(i)
		button.pressed.connect(_learn.bind(i))
		button.mouse_entered.connect(_on_talent_entered.bind(i))
		button.mouse_exited.connect(_hide_tooltip.bind(button))
	for i: int in MAX_TALENT_TABS:
		(_part_n("Tab", i + 1) as BaseButton).pressed.connect(_select_tab.bind(i))
	_tab_gap = _part("Tab2").position.x - _part("Tab1").position.x - _part("Tab1").size.x
	(_part("CloseButton") as BaseButton).pressed.connect(close_requested.emit)
	_portrait = PORTRAIT.instantiate()
	add_child(_portrait)
	var mask: ShaderMaterial = ShaderMaterial.new()
	mask.shader = PORTRAIT_MASK
	var portrait: TextureRect = _part("Portrait")
	portrait.material = mask
	portrait.texture = _portrait.get_texture()
	WowClient.session.object_updated.connect(_on_object_updated)
	visibility_changed.connect(_on_visibility_changed)


# TalentFrame_Update: tabs, points, then the selected tree's buttons and the branches between them.
func refresh() -> void:
	if not is_visible_in_tree():
		return
	_update_specs()
	var session: WowSession = WowClient.session
	var guid: int = _unit()
	if not session.has_object(guid):
		return
	_load_ranks()
	(_part("TalentPointsText") as Label).text = WowStrings.strip_colors(
		WowStrings.get_text("UNSPENT_TALENT_POINTS", "%s")
	) % _points
	_tabs = _pet_tabs() if _spec == Spec.PET \
			else _class_tabs((session.get_field(guid, "UNIT_FIELD_BYTES_0") >> 8) & 0xFF)
	_tab = mini(_tab, maxi(_tabs.size() - 1, 0))
	_update_tabs()
	if _tabs.is_empty():
		return
	var tab_row: int = _talent_tabs.find(_tabs[_tab])
	for piece: String in BACKGROUND_PIECES:
		var background: TextureRect = _part("Background" + piece)
		var file: String = BACKGROUND % [_talent_tabs.get_string(tab_row, "BackgroundFile"), piece]
		var texture: WowTexture = background.texture as WowTexture
		if texture == null or texture.file != file:
			texture = WowTexture.new()
			texture.file = file
			background.texture = texture
	_update_talents()
	_scroll.refresh(true)


func _update_tabs() -> void:
	var x: float = _part("Tab1").position.x
	for i: int in MAX_TALENT_TABS:
		var tab: Control = _part_n("Tab", i + 1)
		tab.visible = i < _tabs.size()
		if not tab.visible:
			continue
		var tab_row: int = _talent_tabs.find(_tabs[i])
		var tab_name: String = _talent_tabs.get_string(tab_row, "Name")
		if i == _tab:
			_points_spent = _spent(_tabs[i])
			(_part("SpentPointsText") as Label).text = WowStrings.format(
				WowStrings.get_text("MASTERY_POINTS_SPENT"), [tab_name, _points_spent]
			)
		(tab.get_node(tab.name + "Text") as Label).text = tab_name
		PanelManager.resize_tab(tab, TAB_PADDING)
		tab.position.x = x
		x += tab.size.x + _tab_gap
		PanelManager.select_tab(tab, i == _tab and not _showing_glyphs())
	var glyph_tab: Control = get_node_or_null("%" + _prefix() + "Tab4")
	if glyph_tab == null:
		return
	(glyph_tab.get_node(glyph_tab.name + "Text") as Label).text = WowStrings.get_text("GLYPHS")
	PanelManager.resize_tab(glyph_tab, TAB_PADDING)
	glyph_tab.position.x = x
	PanelManager.select_tab(glyph_tab, %GlyphFrame.visible)


func _update_talents() -> void:
	var rows: Array = _tab_talents(_tabs[_tab])
	_shown.clear()
	for tier: Array in _branches:
		for node: BranchNode in tier:
			node.reset()
	for i: int in MAX_NUM_TALENTS:
		var button: ItemButton = _button(i)
		button.visible = i < rows.size()
		if not button.visible:
			continue
		var row: int = rows[i]
		_shown.append(row)
		var tier: int = _talents.get_uint(row, "Row")
		var column: int = _talents.get_uint(row, "Column")
		var rank: int = _rank(row)
		button.position = INITIAL_TALENT_OFFSET + Vector2(column, tier) * TALENT_SPACING
		_branches[tier][column].id = i + 1
		button.set_item(WowAssets.spells.icon(_talents.get_uint(row, "RankSpell0")))
		var force_desaturated: bool = _points <= 0 and rank == 0
		var tier_unlocked: bool = tier * POINTS_PER_TIER <= _points_spent
		var slot: CanvasItem = button.get_node("%Slot")
		var rank_border: CanvasItem = button.get_node("%RankBorder")
		var rank_text: Label = button.get_node("%Rank")
		var icon: CanvasItem = button.get_node("%IconTexture")
		rank_text.text = str(rank)
		rank_border.self_modulate = Color.WHITE
		if _set_prereqs(row, tier, column, force_desaturated, tier_unlocked):
			icon.material = null
			icon.self_modulate = Color.WHITE
			var maxed: bool = rank >= _max_rank(row)
			slot.self_modulate = NORMAL_FONT_COLOR if maxed else GREEN_FONT_COLOR
			rank_text.theme_type_variation = \
			&"GameFontNormalSmall" if maxed else &"GameFontGreenSmall"
			rank_border.show()
			rank_text.show()
		else:
			icon.material = _desaturate
			icon.self_modulate = DESATURATED_TINT
			slot.self_modulate = GRAY_FONT_COLOR
			rank_border.visible = rank > 0
			rank_text.visible = rank > 0
			rank_border.self_modulate = GRAY_FONT_COLOR
			rank_text.theme_type_variation = &"GameFontDisableSmall"
	_draw_branches()


# The branch and arrow pieces TalentFrame_DrawLines marked, laid out tier by tier.
func _draw_branches() -> void:
	_branch_index = 0
	_arrow_index = 0
	var ignore_up: bool = false
	for tier: int in MAX_NUM_TALENT_TIERS:
		for column: int in NUM_TALENT_COLUMNS:
			var node: BranchNode = _branches[tier][column]
			var offset: Vector2 = INITIAL_TALENT_OFFSET + Vector2(column, tier) * TALENT_SPACING \
			+ Vector2(2.0, 2.0)
			if node.id:
				if node.up:
					if not ignore_up:
						_set_branch("up", node.up, offset - Vector2(0.0, TALENT_BUTTON_SIZE))
					else:
						ignore_up = false
				if node.down:
					_set_branch("down", node.down, offset + Vector2(0.0, TALENT_BUTTON_SIZE - 1.0))
				if node.left:
					_set_branch("left", node.left, offset - Vector2(TALENT_BUTTON_SIZE, 0.0))
				if node.right:
					var next: BranchNode = _branches[tier][column + 1]
					if next.left and next.down == Branch.UNMET:
						_set_branch("right", next.down, offset + Vector2(TALENT_BUTTON_SIZE, 0.0))
					else:
						_set_branch(
							"right", node.right, offset + Vector2(TALENT_BUTTON_SIZE + 1.0, 0.0)
						)
				var arrow_offset: float = TALENT_BUTTON_SIZE / 2.0 + 5.0
				if node.right_arrow:
					_set_arrow("right", node.right_arrow, offset + Vector2(arrow_offset, 0.0))
				if node.left_arrow:
					_set_arrow("left", node.left_arrow, offset - Vector2(arrow_offset, 0.0))
				if node.top_arrow:
					_set_arrow("top", node.top_arrow, offset - Vector2(0.0, arrow_offset))
			elif node.up and node.left and node.right:
				_set_branch("tup", node.up, offset)
			elif node.down and node.left and node.right:
				_set_branch("tdown", node.down, offset)
			elif node.left and node.down:
				_set_branch("topright", node.left, offset)
				_set_branch("down", node.down, offset + Vector2(0.0, 32.0))
			elif node.left and node.up:
				_set_branch("bottomright", node.left, offset)
			elif node.left and node.right:
				_set_branch("right", node.right, offset + Vector2(TALENT_BUTTON_SIZE, 0.0))
				_set_branch("left", node.left, offset + Vector2(1.0, 0.0))
			elif node.right and node.down:
				_set_branch("topleft", node.right, offset)
				_set_branch("down", node.down, offset + Vector2(0.0, 32.0))
			elif node.right and node.up:
				_set_branch("bottomleft", node.right, offset)
			elif node.up and node.down:
				_set_branch("up", node.up, offset)
				_set_branch("down", node.down, offset + Vector2(0.0, 32.0))
				ignore_up = true
	for i: int in range(_branch_index, MAX_NUM_BRANCH_TEXTURES):
		(_part_n("Branch", i + 1) as CanvasItem).hide()
	for i: int in range(_arrow_index, MAX_NUM_ARROW_TEXTURES):
		(_part_n("Arrow", i + 1) as CanvasItem).hide()


func _set_branch(piece: String, state: Branch, offset: Vector2) -> void:
	_branch_index += 1
	_place(
		_part_n("Branch", _branch_index), BRANCH_COORDS[piece], state, offset,
	)


func _set_arrow(piece: String, state: Branch, offset: Vector2) -> void:
	_arrow_index += 1
	_place(_part_n("Arrow", _arrow_index), ARROW_COORDS[piece], state, offset)


func _place(rect: TextureRect, coords: Array, state: Branch, offset: Vector2) -> void:
	var tex_coord: Array = coords[state - 1]
	var sheet: Texture2D = rect.texture
	if rect.texture is AtlasTexture:
		sheet = (rect.texture as AtlasTexture).atlas
	var sheet_size: Vector2 = sheet.get_size()
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = sheet
	var left: float = minf(tex_coord[0], tex_coord[1])
	var top: float = tex_coord[2]
	atlas.region = Rect2(
		left * sheet_size.x, top * sheet_size.y,
		absf(tex_coord[1] - tex_coord[0]) * sheet_size.x, (tex_coord[3] - top) * sheet_size.y,
	)
	rect.texture = atlas
	rect.flip_h = tex_coord[0] > tex_coord[1]
	rect.position = offset
	rect.show()


# TalentFrame_SetPrereqs: marks the lines to each prerequisite, and whether all of them are met.
func _set_prereqs(row: int, tier: int, column: int, force: bool, unlocked: bool) -> bool:
	var met: bool = unlocked and not force
	for prereq: Vector2i in _prereqs(row):
		var prereq_row: int = _talents.find(prereq.x)
		if _rank(prereq_row) < prereq.y or force:
			met = false
		_draw_lines(
			tier, column, _talents.get_uint(prereq_row, "Row"),
			_talents.get_uint(prereq_row, "Column"), Branch.MET if met else Branch.UNMET,
		)
	return met


# TalentFrame_DrawLines: straight down, straight across, or down then across to the button.
func _draw_lines(
	button_tier: int, button_column: int, tier: int, column: int, state: Branch,
) -> void:
	if button_column == column:
		for i: int in range(tier + 1, button_tier):
			if _branches[i][button_column].id:
				return
		for i: int in range(tier, button_tier):
			_branches[i][button_column].down = state
			if i + 1 <= button_tier - 1:
				_branches[i + 1][button_column].up = state
		_branches[button_tier][button_column].top_arrow = state
		return
	var left: int = mini(button_column, column)
	var right: int = maxi(button_column, column)
	if button_tier == tier:
		for i: int in range(left + 1, right):
			if _branches[tier][i].id:
				return
		for i: int in range(left, right):
			_branches[tier][i].right = state
			_branches[tier][i + 1].left = state
		if button_column < column:
			_branches[button_tier][button_column].right_arrow = state
		else:
			_branches[button_tier][button_column].left_arrow = state
		return
	var first: int = left + 1 if left == column else left
	var last: int = right if left == column else right - 1
	var blocked: bool = false
	for i: int in range(first, last + 1):
		if _branches[tier][i].id:
			blocked = true
	if not blocked:
		_branches[tier][button_column].down = state
		_branches[button_tier][button_column].up = state
		for i: int in range(tier, button_tier):
			_branches[i][button_column].down = state
			_branches[i + 1][button_column].up = state
		for i: int in range(left, right):
			_branches[tier][i].right = state
			_branches[tier][i + 1].left = state
		_branches[button_tier][button_column].top_arrow = state
		return
	first = left + 1 if left == button_column else left
	last = right if left == button_column else right - 1
	for i: int in range(first, last + 1):
		if _branches[button_tier][i].id:
			return
	for i: int in range(tier, button_tier):
		_branches[i][column].up = state
		_branches[i + 1][column].down = state
	if button_column < column:
		_branches[button_tier][button_column].right_arrow = state
	else:
		_branches[button_tier][button_column].left_arrow = state


# GetTalentTabInfo order: the class's trees by OrderIndex.
func _class_tabs(class_id: int) -> Array[int]:
	var tabs: Array[int] = []
	var order: Dictionary[int, int] = {}
	for row: int in _talent_tabs.row_count():
		if _talent_tabs.get_uint(row, "ClassMask") & (1 << (class_id - 1)):
			var id: int = _talent_tabs.get_uint(row, "ID")
			tabs.append(id)
			order[id] = _talent_tabs.get_uint(row, "OrderIndex")
	tabs.sort_custom(func(a: int, b: int) -> bool: return order[a] < order[b])
	return tabs


# GetTalentInfo order: a tree's talents by tier, then column.
func _tab_talents(tab_id: int) -> Array:
	if not _tab_rows.has(tab_id):
		var rows: Array[int] = []
		for row: int in _talents.row_count():
			if _talents.get_uint(row, "TabID") == tab_id:
				rows.append(row)
		rows.sort_custom(func(a: int, b: int) -> bool:
			return _talents.get_uint(a, "Row") * NUM_TALENT_COLUMNS + _talents.get_uint(a, "Column") \
			< _talents.get_uint(b, "Row") * NUM_TALENT_COLUMNS + _talents.get_uint(b, "Column")
		)
		_tab_rows[tab_id] = rows
	return _tab_rows[tab_id]


func _rank(row: int) -> int:
	if _spec == Spec.PET or not _viewing_active():
		return _viewed_ranks().get(_talents.get_uint(row, "ID"), 0)
	for i: int in range(MAX_RANKS - 1, -1, -1):
		if _known.has(_talents.get_uint(row, "RankSpell%d" % i)):
			return i + 1
	return 0


# The node names' first part, which the inspect tree swaps for its own.
func _prefix() -> String:
	return "PlayerTalentFrame"


func _unit() -> int:
	if _spec == Spec.PET:
		return WowClient.pet.guid
	return WowClient.session.get_player_guid()


# The active spec's ranks are the talent spells the player knows; the others come from TALENTS_INFO.
func _load_ranks() -> void:
	var session: WowSession = WowClient.session
	var talents: Talents = WowClient.talents
	_known.clear()
	for spell: int in session.get_known_spells():
		_known[spell] = true
	_points = session.get_field(session.get_player_guid(), "PLAYER_CHARACTER_POINTS1")
	if _spec == Spec.PET:
		_points = talents.pet_unspent
	elif not _viewing_active():
		# Both groups have the same points to spend; only the active one's are counted in the field.
		_points += _total(talents.groups[talents.active_group]["ranks"]) - _total(_viewed_ranks())


func _showing_glyphs() -> bool:
	return has_node("%GlyphFrame") and %GlyphFrame.visible


func _part(piece: String) -> Control:
	return get_node("%" + _prefix() + piece)


func _part_n(piece: String, number: int) -> Control:
	return get_node("%%%s%s%d" % [_prefix(), piece, number])


func _max_rank(row: int) -> int:
	var ranks: int = 0
	while ranks < MAX_RANKS and _talents.get_uint(row, "RankSpell%d" % ranks):
		ranks += 1
	return ranks


# Each prerequisite as its talent id and the rank it needs.
func _prereqs(row: int) -> Array[Vector2i]:
	var prereqs: Array[Vector2i] = []
	for i: int in MAX_PREREQS:
		var talent: int = _talents.get_uint(row, "PrereqTalent%d" % i)
		if talent:
			prereqs.append(Vector2i(talent, _talents.get_uint(row, "PrereqRank%d" % i) + 1))
	return prereqs


func _spent(tab_id: int) -> int:
	var spent: int = 0
	for row: int in _tab_talents(tab_id):
		spent += _rank(row)
	return spent


func _button(index: int) -> ItemButton:
	return _part_n("Talent", index + 1)


func _select_tab(tab: int) -> void:
	_tab = tab
	_show_glyph_frame(false)
	refresh()


# PlayerTalentFrame_ShowGlyphFrame: the glyph sockets take the talent tree's place.
func show_glyphs() -> void:
	_show_glyph_frame(true)
	refresh()


func _show_glyph_frame(shown: bool) -> void:
	%GlyphFrame.visible = shown
	_part("ScrollFrame").visible = not shown


func _learnable(row: int) -> bool:
	if _spec != Spec.PET and not _viewing_active():
		return false
	var tier_unlocked: bool = _talents.get_uint(row, "Row") * POINTS_PER_TIER <= _points_spent
	if _points <= 0 or not tier_unlocked or _rank(row) >= _max_rank(row):
		return false
	for prereq: Vector2i in _prereqs(row):
		if _rank(_talents.find(prereq.x)) < prereq.y:
			return false
	return true


# LearnTalent sends the next rank, counted from 0.
func _learn(index: int) -> void:
	if index >= _shown.size() or not _learnable(_shown[index]):
		return
	var row: int = _shown[index]
	var payload: PackedByteArray = PackedByteArray()
	if _spec == Spec.PET:
		payload.resize(8)
		payload.encode_u64(0, WowClient.pet.guid)
	payload.resize(payload.size() + 8)
	payload.encode_u32(payload.size() - 8, _talents.get_uint(row, "ID"))
	payload.encode_u32(payload.size() - 4, _rank(row))
	WowClient.session.send_packet(
		"CMSG_PET_LEARN_TALENT" if _spec == Spec.PET else "CMSG_LEARN_TALENT", payload
	)


# GameTooltip:SetTalent: name and rank, unmet requirements, this rank's text, then the next rank's.
func _on_talent_entered(index: int) -> void:
	var tooltip: GameTooltip = GameTooltip.current
	if tooltip == null or index >= _shown.size():
		return
	var row: int = _shown[index]
	var rank: int = _rank(row)
	var max_rank: int = _max_rank(row)
	var spells: SpellInfo = WowAssets.spells
	var button: ItemButton = _button(index)
	tooltip.begin(button, GameTooltip.TooltipAnchor.RIGHT, button)
	tooltip.add_line(spells.spell_name(_talents.get_uint(row, "RankSpell0")))
	tooltip.add_line(WowStrings.get_text("TOOLTIP_TALENT_RANK") % [rank, max_rank])
	var tier_points: int = _talents.get_uint(row, "Row") * POINTS_PER_TIER
	if tier_points > _points_spent:
		var tab_name: String = _talent_tabs.get_string(_talent_tabs.find(_tabs[_tab]), "Name")
		tooltip.add_line(
			WowStrings.get_text("TOOLTIP_TALENT_TIER_POINTS") % [tier_points, tab_name],
			GameTooltip.RED,
		)
	for prereq: Vector2i in _prereqs(row):
		var prereq_row: int = _talents.find(prereq.x)
		if _rank(prereq_row) < prereq.y:
			var prereq_name: String = spells.spell_name(_talents.get_uint(prereq_row, "RankSpell0"))
			tooltip.add_line(
				WowStrings.get_text("TOOLTIP_TALENT_PREREQ") % [prereq.y, prereq_name],
				GameTooltip.RED,
			)
	var spell: int = _talents.get_uint(row, "RankSpell%d" % maxi(rank - 1, 0))
	tooltip.add_line(SpellText.describe(spell), NORMAL_FONT_COLOR, true)
	if rank > 0 and rank < max_rank:
		tooltip.add_line(" ")
		tooltip.add_line(WowStrings.get_text("TOOLTIP_TALENT_NEXT_RANK"))
		var next: int = _talents.get_uint(row, "RankSpell%d" % rank)
		tooltip.add_line(SpellText.describe(next), NORMAL_FONT_COLOR, true)
	if _learnable(row):
		tooltip.add_line(WowStrings.get_text("TOOLTIP_TALENT_LEARN"), GREEN_FONT_COLOR)
	tooltip.present()


func _hide_tooltip(tooltip_owner: Control) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(tooltip_owner)


func _on_object_updated(guid: int) -> void:
	if guid == _unit():
		refresh()


func _select_spec(spec: Spec) -> void:
	_spec = spec
	_tab = 0
	_show_glyph_frame(false)
	_portrait.show_unit(_unit())
	refresh()


# PlayerTalentFrame_UpdateSpecs and _UpdateControls: a tab per talent group, then the pet's tree.
func _update_specs() -> void:
	var talents: Talents = WowClient.talents
	var dual: bool = talents.groups.size() > 1
	var shown: Array[bool] = [true, dual, _pet_family_row() >= 0]
	if not shown[_spec]:
		_spec = Spec.PRIMARY
	var top: float = SPEC_TAB_TOP
	for spec: Spec in [Spec.PRIMARY, Spec.SECONDARY, Spec.PET]:
		var tab: WowButton = _spec_tab(spec)
		tab.visible = shown[spec]
		tab.checked = spec == _spec
		if not tab.visible:
			continue
		if spec == Spec.PET and top > SPEC_TAB_TOP:
			top += PET_SPEC_TAB_GAP - SPEC_TAB_GAP
		tab.offset_bottom = top + tab.size.y
		tab.offset_top = top
		top += tab.size.y + SPEC_TAB_GAP
		(tab.get_node("NormalTexture") as TextureRect).texture = _spec_icon(spec)
	var player_spec: bool = _spec != Spec.PET
	_part("StatusFrame").visible = dual and player_spec and _viewing_active()
	_part("ActivateButton").visible = dual and player_spec and not _viewing_active()
	_part("Tab4").visible = player_spec
	var glyph_frame: GlyphFrame = %GlyphFrame
	glyph_frame.inactive_glyphs = _viewed_glyphs()


# The primary tree's icon for a talent group, as TalentFrame_UpdateSpecInfoCache picks it.
func _spec_icon(spec: Spec) -> Texture2D:
	if spec == Spec.PET:
		return WowAssets.spells.icon_texture(_families.get_string(_pet_family_row(), "IconFile"))
	var ranks: Dictionary[int, int] = _group_ranks(spec)
	var class_id: int = (WowClient.session.get_field(
		WowClient.session.get_player_guid(), "UNIT_FIELD_BYTES_0"
	) >> 8) & 0xFF
	var tabs: Array[int] = _class_tabs(class_id)
	var spent: Array[int] = []
	for tab_id: int in tabs:
		var points: int = 0
		for row: int in _tab_talents(tab_id):
			points += ranks.get(_talents.get_uint(row, "ID"), 0)
		spent.append(points)
	var sorted: Array[int] = spent.duplicate()
	sorted.sort()
	var file: String = DEFAULT_SPEC_ICON
	if not sorted.is_empty() and sorted[-1] > 0:
		var low: int = sorted[0]
		var high: int = sorted[-1]
		if 3 * (sorted[sorted.size() >> 1] - low) < 2 * (high - low):
			var icon_id: int = _talent_tabs.get_uint(
				_talent_tabs.find(tabs[spent.find(high)]), "SpellIconID"
			)
			file = WowAssets.spells.icon_path(icon_id)
		elif tabs.size() > 1:
			file = HYBRID_ICON
	return WowAssets.spells.icon_texture(file)


func _spec_tab(spec: Spec) -> WowButton:
	return get_node("%%PlayerSpecTab%d" % (spec + 1))


func _viewing_active() -> bool:
	return _spec == Spec.PET or WowClient.talents.groups.size() < 2 \
			or _spec == WowClient.talents.active_group


func _viewed_ranks() -> Dictionary[int, int]:
	if _spec == Spec.PET:
		return WowClient.talents.pet_ranks
	return _group_ranks(_spec)


func _group_ranks(spec: Spec) -> Dictionary[int, int]:
	var groups: Array[Dictionary] = WowClient.talents.groups
	var ranks: Dictionary[int, int] = {}
	if spec < groups.size():
		ranks.assign(groups[spec]["ranks"])
	return ranks


func _viewed_glyphs() -> PackedInt32Array:
	var groups: Array[Dictionary] = WowClient.talents.groups
	if _spec == Spec.PET or _viewing_active() or _spec >= groups.size():
		return PackedInt32Array()
	return groups[_spec]["glyphs"]


func _total(ranks: Dictionary[int, int]) -> int:
	var total: int = 0
	for points: int in ranks.values():
		total += points
	return total


# The hunter pet's CreatureFamily row while it has a talent tree, or -1.
func _pet_family_row() -> int:
	var pet: Pet = WowClient.pet
	if not WowClient.talents.has_pet_talents or pet.guid == 0 or not pet.is_hunter_pet():
		return -1
	var row: int = _families.find(WowClient.session.get_creature_info(pet.guid).get("family", 0))
	return row if row >= 0 and _families.get_int(row, "PetTalentType") >= 0 else -1


# GetTalentTabInfo for a pet: the one tree whose PetTalentMask takes the family's talent type.
func _pet_tabs() -> Array[int]:
	var tabs: Array[int] = []
	var row: int = _pet_family_row()
	if row < 0:
		return tabs
	var type_bit: int = 1 << _families.get_int(row, "PetTalentType")
	for tab_row: int in _talent_tabs.row_count():
		if _talent_tabs.get_uint(tab_row, "PetTalentMask") & type_bit:
			tabs.append(_talent_tabs.get_uint(tab_row, "ID"))
	return tabs


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_portrait.show_unit(_unit())
	refresh()


class BranchNode:
	var id: int = 0
	var up: Branch = Branch.NONE
	var down: Branch = Branch.NONE
	var left: Branch = Branch.NONE
	var right: Branch = Branch.NONE
	var left_arrow: Branch = Branch.NONE
	var right_arrow: Branch = Branch.NONE
	var top_arrow: Branch = Branch.NONE

	func reset() -> void:
		id = 0
		up = Branch.NONE
		down = Branch.NONE
		left = Branch.NONE
		right = Branch.NONE
		left_arrow = Branch.NONE
		right_arrow = Branch.NONE
		top_arrow = Branch.NONE
