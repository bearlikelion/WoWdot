class_name CharacterCreate
extends Control

signal create_requested(character: Dictionary)
signal back_requested

const RACE_BUTTONS: int = 8
const CLASS_BUTTONS: int = 8
const CUSTOMIZATIONS: Array[CharacterModels.Option] = [
	CharacterModels.Option.SKIN,
	CharacterModels.Option.FACE,
	CharacterModels.Option.HAIR_STYLE,
	CharacterModels.Option.HAIR_COLOR,
	CharacterModels.Option.FACIAL_HAIR,
]
const OPTION_KEYS: Dictionary[CharacterModels.Option, String] = {
	CharacterModels.Option.SKIN: "skin",
	CharacterModels.Option.FACE: "face",
	CharacterModels.Option.HAIR_STYLE: "hair_style",
	CharacterModels.Option.HAIR_COLOR: "hair_color",
	CharacterModels.Option.FACIAL_HAIR: "facial_hair",
}
# RACE_ICON_TCOORDS as cells of the 4x4 race icon sheet; female icons sit two rows lower.
const RACE_ICON_CELLS: Dictionary[String, Vector2i] = {
	"Human": Vector2i(0, 0), "Dwarf": Vector2i(1, 0), "Gnome": Vector2i(2, 0),
	"NightElf": Vector2i(3, 0), "Tauren": Vector2i(0, 1), "Scourge": Vector2i(1, 1),
	"Troll": Vector2i(2, 1), "Orc": Vector2i(3, 1),
}
const RACE_ICON_CELL: float = 0.25
# CLASS_ICON_TCOORDS as left, top, width and height.
const CLASS_ICON_RECTS: Dictionary[String, Rect2] = {
	"WARRIOR": Rect2(0.0, 0.0, 0.25, 0.25),
	"MAGE": Rect2(0.25, 0.0, 0.24609375, 0.25),
	"ROGUE": Rect2(0.49609375, 0.0, 0.24609375, 0.25),
	"DRUID": Rect2(0.7421875, 0.0, 0.24609375, 0.25),
	"HUNTER": Rect2(0.0, 0.25, 0.25, 0.25),
	"SHAMAN": Rect2(0.25, 0.25, 0.24609375, 0.25),
	"PRIEST": Rect2(0.49609375, 0.25, 0.24609375, 0.25),
	"WARLOCK": Rect2(0.7421875, 0.25, 0.24609375, 0.25),
	"PALADIN": Rect2(0.0, 0.5, 0.25, 0.25),
}
const GENDER_ICON_RECTS: Array[Rect2] = [Rect2(0.0, 0.0, 0.5, 1.0), Rect2(0.5, 0.0, 0.5, 1.0)]
const FACTION_ICON_RECTS: Array[Rect2] = [Rect2(0.0, 0.0, 0.5, 1.0), Rect2(0.5, 0.0, 0.5, 1.0)]
const FACTION_KEYS: Array[String] = ["ALLIANCE", "HORDE"]
# FACTION_BACKDROP_COLOR_TABLE: the info panels' background by faction.
const FACTION_BACKGROUNDS: Array[Color] = [Color(0.09, 0.09, 0.19), Color(0.19, 0.05, 0.05)]
const NAME_BORDER: Color = Color(0.5, 0.5, 0.5)
# FontStrings in the info panels hang two units under the one above them.
const TEXT_GAP: float = 2.0
const INITIAL_FACING: float = -15.0
const DRAG_DEGREES_PER_PIXEL: float = 0.6
const ROTATE_DEGREES_PER_SECOND: float = 120.0

var _look: Dictionary = {}
var _classes: Array[int] = []
var _class_id: int = 0
var _race_buttons: Array[WowButton] = []
var _class_buttons: Array[WowButton] = []
var _gender_buttons: Array[WowButton] = []

@onready var _model: WowModelFrame = %CharacterCreateModel
@onready var _name_edit: LineEdit = %CharacterCreateNameEdit
@onready var _rotate_left: BaseButton = %CharacterCreateRotateLeft
@onready var _rotate_right: BaseButton = %CharacterCreateRotateRight


func _ready() -> void:
	for i: int in RACE_BUTTONS:
		var button: WowButton = get_node("%%CharacterCreateRaceButton%d" % (i + 1))
		_race_buttons.append(button)
		button.pressed.connect(_choose_race.bind(CharacterOptions.RACE_ORDER[i]))
	for i: int in CLASS_BUTTONS:
		var button: WowButton = get_node("%%CharacterCreateClassButton%d" % (i + 1))
		_class_buttons.append(button)
		button.pressed.connect(_choose_class.bind(i))
	_gender_buttons.assign([%CharacterCreateGenderButtonMale, %CharacterCreateGenderButtonFemale])
	for gender: int in _gender_buttons.size():
		var icon: TextureRect = _gender_buttons[gender].get_node("NormalTexture")
		_set_tex_coords(icon, GENDER_ICON_RECTS[gender])
		_gender_buttons[gender].pressed.connect(_choose_gender.bind(gender))
	for i: int in CUSTOMIZATIONS.size():
		var frame: String = "%%CharacterCustomizationButtonFrame%d" % (i + 1)
		(get_node(frame + "Text") as Label).text = WowStrings.get_text(
			"CHAR_CUSTOMIZATION%d_DESC" % (i + 1)
		)
		var left: BaseButton = get_node(frame + "LeftButton")
		var right: BaseButton = get_node(frame + "RightButton")
		left.pressed.connect(_cycle.bind(CUSTOMIZATIONS[i], -1))
		right.pressed.connect(_cycle.bind(CUSTOMIZATIONS[i], 1))
	for label: Label in [
		%CharacterCreateFactionText, %CharacterCreateRaceText, %CharacterCreateRaceAbilityText,
		%CharacterCreateClassText,
	]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var name_backdrop: WowBackdrop = _name_edit.get_node("Backdrop")
	name_backdrop.border_color = NAME_BORDER
	name_backdrop.background_color = FACTION_BACKGROUNDS[CharacterOptions.Faction.ALLIANCE]
	_name_edit.text_submitted.connect(func(_text: String) -> void: _accept())
	%CharCreateRandomizeButton.pressed.connect(_randomize_look)
	%CharCreateOkayButton.pressed.connect(_accept)
	%CharCreateBackButton.pressed.connect(back_requested.emit)
	%CharacterCreateFrame.gui_input.connect(_on_drag)
	visibility_changed.connect(_on_visibility_changed)


func _process(delta: float) -> void:
	var turn: float = float(_rotate_right.button_pressed) - float(_rotate_left.button_pressed)
	if turn != 0.0:
		_model.facing += turn * ROTATE_DEGREES_PER_SECOND * delta


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_accept()


# CharacterCreate_OnShow: a random race and look, the race's first class and a blank name.
func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	_look = {"gender": randi_range(0, 1)}
	_name_edit.text = ""
	_choose_race(CharacterOptions.RACE_ORDER.pick_random())
	_name_edit.grab_focus.call_deferred()


func _choose_race(race: int) -> void:
	_look["race"] = race
	_randomize_look()
	var faction: CharacterOptions.Faction = CharacterOptions.faction(race)
	_set_tex_coords(%CharacterCreateFactionIcon, FACTION_ICON_RECTS[faction])
	%CharacterCreateFactionLabel.text = WowStrings.get_text(FACTION_KEYS[faction])
	%CharacterCreateFactionText.text = WowStrings.get_text("FACTION_INFO_" + FACTION_KEYS[faction])
	var file: String = CharacterOptions.race_file(race).to_upper()
	%CharacterCreateRaceLabel.text = CharacterOptions.race_name(race)
	%CharacterCreateRaceText.text = WowStrings.get_text("RACE_INFO_" + file)
	var abilities: PackedStringArray = []
	while WowStrings.get_text("ABILITY_INFO_%s%d" % [file, abilities.size() + 1], "-") != "-":
		abilities.append(WowStrings.get_text("ABILITY_INFO_%s%d" % [file, abilities.size() + 1]))
	%CharacterCreateRaceAbilityText.text = "\n\n".join(abilities)
	for panel: Control in [
		%CharacterCreateCharacterRace,
		%CharacterCreateCharacterClass,
		%CharacterCreateCharacterFaction,
	]:
		(panel.get_node("Backdrop") as WowBackdrop).background_color = FACTION_BACKGROUNDS[faction]
	CharacterOptions.apply_scene(_model, race)
	_classes = CharacterOptions.classes_for(race)
	for i: int in CLASS_BUTTONS:
		_class_buttons[i].visible = i < _classes.size()
		if _class_buttons[i].visible:
			var icon: TextureRect = _class_buttons[i].get_node("NormalTexture")
			_set_tex_coords(icon, CLASS_ICON_RECTS[CharacterOptions.class_file(_classes[i])])
	_choose_class(0)
	_refresh_gender()
	_model.facing = INITIAL_FACING
	_stack_texts()


func _choose_class(index: int) -> void:
	_class_id = _classes[index]
	for i: int in _class_buttons.size():
		_mark(_class_buttons[i], i == index, CharacterOptions.class_label(_class_id))
	var class_file: String = CharacterOptions.class_file(_class_id)
	_set_tex_coords(%CharacterCreateClassIcon, CLASS_ICON_RECTS[class_file])
	%CharacterCreateClassLabel.text = CharacterOptions.class_label(_class_id)
	%CharacterCreateClassText.text = WowStrings.get_text("CLASS_" + class_file)
	_stack_texts()


func _choose_gender(gender: int) -> void:
	_look["gender"] = gender
	_randomize_look()
	_refresh_gender()


# Race icons change with gender, and so does what the facial hair option is called.
func _refresh_gender() -> void:
	var race: int = _look["race"]
	var gender: CharacterOptions.Gender = _look["gender"]
	for i: int in RACE_BUTTONS:
		var shown_race: int = CharacterOptions.RACE_ORDER[i]
		_set_tex_coords(_race_buttons[i].get_node("NormalTexture"), _race_icon(shown_race, gender))
		_mark(_race_buttons[i], shown_race == race, CharacterOptions.race_name(race))
	for i: int in _gender_buttons.size():
		_mark(_gender_buttons[i], i == gender, WowStrings.get_text(["MALE", "FEMALE"][i]))
	_set_tex_coords(%CharacterCreateRaceIcon, _race_icon(race, gender))
	var hair: String = CharacterOptions.hair_kind(race)
	%CharacterCustomizationButtonFrame3Text.text = WowStrings.get_text("HAIR_%s_STYLE" % hair)
	%CharacterCustomizationButtonFrame4Text.text = WowStrings.get_text("HAIR_%s_COLOR" % hair)
	var facial: String = CharacterOptions.facial_hair_kind(race, gender)
	%CharacterCustomizationButtonFrame5.visible = facial != "NONE"
	%CharacterCustomizationButtonFrame5Text.text = WowStrings.get_text("FACIAL_HAIR_" + facial)


func _cycle(option: CharacterModels.Option, step: int) -> void:
	var count: int = WowAssets.characters.option_count(_look, option)
	if count > 0:
		_look[OPTION_KEYS[option]] = posmod(_look.get(OPTION_KEYS[option], 0) + step, count)
	# Faces follow the skin colour and hair colours the style, so the later choice is re-clamped.
	for later: CharacterModels.Option in CUSTOMIZATIONS.slice(CUSTOMIZATIONS.find(option) + 1):
		var later_count: int = WowAssets.characters.option_count(_look, later)
		_look[OPTION_KEYS[later]] = mini(_look.get(OPTION_KEYS[later], 0), maxi(later_count - 1, 0))
	_show_character()


func _randomize_look() -> void:
	for option: CharacterModels.Option in CUSTOMIZATIONS:
		var count: int = WowAssets.characters.option_count(_look, option)
		_look[OPTION_KEYS[option]] = randi_range(0, maxi(count - 1, 0))
	_show_character()


func _show_character() -> void:
	_model.show_character(CharacterOptions.character_model(_look))


func _accept() -> void:
	var character: Dictionary = _look.duplicate()
	character["name"] = _name_edit.text.strip_edges()
	character["class"] = _class_id
	create_requested.emit(character)


func _race_icon(race: int, gender: CharacterOptions.Gender) -> Rect2:
	var cell: Vector2i = RACE_ICON_CELLS[CharacterOptions.race_file(race)]
	var row: int = cell.y + (2 if gender == CharacterOptions.Gender.FEMALE else 0)
	return Rect2(Vector2(cell.x, row) * RACE_ICON_CELL, Vector2.ONE * RACE_ICON_CELL)


# SetChecked and LockHighlight on the chosen button, with its name shown under it.
func _mark(button: WowButton, chosen: bool, label: String) -> void:
	button.checked = chosen
	button.highlight_locked = chosen
	(get_node("%" + button.name + "HighlightText") as Label).text = label if chosen else ""


# The info texts anchor to the bottom of the text above, which only exists once they are wrapped.
func _stack_texts() -> void:
	for column: Array in [
		[%CharacterCreateFactionLabel, %CharacterCreateFactionText],
		[%CharacterCreateRaceLabel, %CharacterCreateRaceText, %CharacterCreateRaceAbilityText],
		[%CharacterCreateClassLabel, %CharacterCreateClassText],
	]:
		for i: int in range(1, column.size()):
			var above: Label = column[i - 1]
			var below: Label = column[i]
			below.position.y = above.position.y + above.get_minimum_size().y + TEXT_GAP
	for scroll: WowScrollFrame in [
		%CharacterCreateFactionScrollFrame, %CharacterCreateRaceScrollFrame,
		%CharacterCreateClassScrollFrame,
	]:
		scroll.refresh()


# WoW's SetTexCoord: the region, in 0..1 of the texture, that the rect shows.
func _set_tex_coords(rect: TextureRect, region: Rect2) -> void:
	var atlas: AtlasTexture = rect.texture as AtlasTexture
	if atlas == null:
		atlas = AtlasTexture.new()
		atlas.atlas = rect.texture
		rect.texture = atlas
	var size: Vector2 = atlas.atlas.get_size()
	atlas.region = Rect2(region.position * size, region.size * size)


func _on_drag(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_model.facing += motion.relative.x * DRAG_DEGREES_PER_PIXEL
