class_name CraftFrame
extends Control

signal close_requested
signal open_requested

const CRAFTS_DISPLAYED: int = 8
const CRAFT_HEIGHT: float = 16.0
const MAX_REAGENTS: int = 8
# CraftTypeColor and CraftSubTypeColor: Beast Training lists what it can teach as "none".
const TRAINABLE: Color = Color(0.25, 0.75, 0.25)
const TRAINABLE_RANK: Color = Color(0.0, 0.45, 0.0)
const USED: Color = Color(0.5, 0.5, 0.5)
const SELECTED_TEXT: Color = Color(1.0, 1.0, 1.0)
const TOO_LOW: Color = Color(1.0, 0.125, 0.125)
# CraftFrame_Update: without headers the names start here, and the rank follows 10 after.
const TEXT_LEFT: float = 3.0
const RANK_GAP: float = 10.0
# The points label sits this far left of the number.
const POINTS_GAP: float = 5.0

var _abilities: Array[Dictionary] = []
# The selected Beast Training spell, which is what gets cast to teach the pet.
var _selected: int = 0
var _offset: int = 0

@onready var _list_scroll: WowScrollFrame = %CraftListScrollFrame
@onready var _train: BaseButton = %CraftCreateButton


func _ready() -> void:
	for i: int in CRAFTS_DISPLAYED:
		_row(i).pressed.connect(_on_row_pressed.bind(i))
	# Beast Training has no skill rank, headers or reagents.
	for unused: CanvasItem in [%CraftRankFrame, %CraftExpandButtonFrame, %CraftReagentLabel]:
		unused.hide()
	for i: int in MAX_REAGENTS:
		(get_node("%%CraftReagent%d" % (i + 1)) as CanvasItem).hide()
	%CraftFrameTitleText.text = WowAssets.spells.spell_name(BeastTraining.SPELL)
	%CraftFramePointsLabel.text = WowStrings.get_text("TRAINING_POINTS")
	%CraftCreateButtonText.text = WowStrings.get_text("TRAIN")
	_train.pressed.connect(_on_train_pressed)
	%CraftCancelButton.pressed.connect(close_requested.emit)
	%CraftFrameCloseButton.pressed.connect(close_requested.emit)
	_list_scroll.scrolled.connect(_on_list_scrolled)
	var icon: TextureButton = %CraftIcon
	icon.ignore_texture_size = true
	icon.stretch_mode = TextureButton.STRETCH_SCALE
	WowClient.pet.changed.connect(_on_pet_changed)
	WowClient.session.object_updated.connect(_on_object_updated)


func set_portrait(texture: Texture2D) -> void:
	(%CraftFramePortrait as TextureRect).texture = texture


# Casting Beast Training opens the window; false for every other spell.
func open_for_spell(spell_id: int) -> bool:
	if spell_id != BeastTraining.SPELL:
		return false
	_selected = 0
	_offset = 0
	open_requested.emit()
	refresh()
	return true


# CraftFrame_Update.
func refresh() -> void:
	if not is_visible_in_tree():
		return
	_abilities = BeastTraining.abilities()
	if _ability().is_empty() and not _abilities.is_empty():
		_selected = _abilities[0]["spell"]
	var has_pet: bool = WowClient.pet.is_hunter_pet()
	%CraftFramePointsLabel.visible = has_pet
	%CraftFramePointsText.visible = has_pet
	var points_text: Label = %CraftFramePointsText
	points_text.text = str(BeastTraining.points())
	var points_label: Label = %CraftFramePointsLabel
	points_label.offset_right = points_text.offset_right - _width(points_text) - POINTS_GAP
	points_label.offset_left = points_label.offset_right
	var hidden_rows: int = maxi(_abilities.size() - CRAFTS_DISPLAYED, 0)
	_list_scroll.visible = hidden_rows > 0
	_list_scroll.set_range(hidden_rows * CRAFT_HEIGHT)
	_offset = mini(_offset, hidden_rows)
	var highlight: Control = %CraftHighlightFrame
	highlight.hide()
	for i: int in CRAFTS_DISPLAYED:
		var row: WowButton = _row(i)
		var index: int = i + _offset
		row.visible = index < _abilities.size()
		if not row.visible:
			continue
		var ability: Dictionary = _abilities[index]
		var selected: bool = ability["spell"] == _selected
		var color: Color = USED if ability["used"] else TRAINABLE
		var text: Label = get_node("%%Craft%dText" % (i + 1))
		text.text = " " + ability["name"]
		text.self_modulate = color
		text.offset_left = TEXT_LEFT
		text.offset_right = TEXT_LEFT
		var rank: Label = get_node("%%Craft%dSubText" % (i + 1))
		rank.text = WowStrings.get_text("PARENS_TEMPLATE") % ability["rank"] \
				if not ability["rank"].is_empty() else ""
		rank.offset_left = TEXT_LEFT + _width(text) + RANK_GAP
		rank.offset_right = rank.offset_left + _width(rank)
		rank.self_modulate = SELECTED_TEXT if selected \
				else (USED if ability["used"] else TRAINABLE_RANK)
		var cost: Label = get_node("%%Craft%dCost" % (i + 1))
		cost.text = WowStrings.get_text("TRAINER_LIST_TP") % ability["cost"] \
				if ability["cost"] > 0 else ""
		cost.self_modulate = SELECTED_TEXT if selected else color
		(row.get_node("NormalTexture") as TextureRect).texture = null
		row.highlight_locked = selected
		if selected:
			highlight.position = row.position
			(%CraftHighlight as CanvasItem).self_modulate = color
			highlight.show()
	_update_details()


# CraftFrame_SetSelection: what the ability does, the pet level it needs and its cost.
func _update_details() -> void:
	var ability: Dictionary = _ability()
	(%CraftDetailScrollChildFrame as CanvasItem).visible = not ability.is_empty()
	_train.disabled = true
	if ability.is_empty():
		return
	%CraftName.text = ability["name"]
	(%CraftIcon as TextureButton).texture_normal = WowAssets.spells.icon(ability["taught"])
	%CraftDescription.text = SpellText.describe(ability["taught"])
	var pet_level: int = WowClient.session.get_field(WowClient.pet.guid, "UNIT_FIELD_LEVEL")
	var requirements: Label = %CraftRequirements
	requirements.visible = ability["level"] > 0
	requirements.text = "%s %s" % [
		WowStrings.get_text("REQUIRES_LABEL"),
		WowStrings.strip_colors(WowStrings.get_text("TRAINER_PET_LEVEL") % ability["level"]),
	]
	requirements.self_modulate = TOO_LOW if pet_level < ability["level"] else Color.WHITE
	var points: int = BeastTraining.points()
	var cost: Label = %CraftCost
	cost.visible = ability["cost"] > 0
	cost.text = "%s %d %s" % [
		WowStrings.get_text("COSTS_LABEL"), ability["cost"],
		WowStrings.get_text("TRAINING_POINTS_LABEL"),
	]
	cost.self_modulate = TOO_LOW if points < ability["cost"] else Color.WHITE
	_train.disabled = ability["used"] or pet_level < ability["level"] or points < ability["cost"]


func _width(label: Label) -> float:
	return label.get_theme_font("font").get_string_size(
		label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")
	).x


func _ability() -> Dictionary:
	for ability: Dictionary in _abilities:
		if ability["spell"] == _selected:
			return ability
	return {}


func _row(index: int) -> WowButton:
	return get_node("%%Craft%d" % (index + 1))


func _on_row_pressed(index: int) -> void:
	_selected = _abilities[index + _offset]["spell"]
	refresh()


func _on_list_scrolled(value: float) -> void:
	var offset: int = roundi(value / CRAFT_HEIGHT)
	if offset != _offset:
		_offset = offset
		refresh()


# DoCraft: the Beast Training spell finds the pet itself, and an explicit target is refused.
func _on_train_pressed() -> void:
	var ability: Dictionary = _ability()
	if not ability.is_empty():
		WowClient.session.cast_spell(ability["spell"])


func _on_pet_changed() -> void:
	refresh.call_deferred()


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.pet.guid or guid == WowClient.session.get_player_guid():
		refresh.call_deferred()
