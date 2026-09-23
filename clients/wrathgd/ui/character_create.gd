class_name CharacterCreate
extends Control

signal create_requested(character: Dictionary)
signal service_accepted(character: Dictionary, service: Service)
signal back_requested

# PAID_CHARACTER_CUSTOMIZATION, PAID_RACE_CHANGE and PAID_FACTION_CHANGE.
enum Service { NONE, CUSTOMIZE, RACE_CHANGE, FACTION_CHANGE }

const DEATH_KNIGHT: int = 6
const DEATH_KNIGHT_LEVEL: int = 55
const PANEL_BUTTONS: PackedStringArray = [
	"CharCreateOkayButton", "CharCreateBackButton", "CharCreateRandomizeButton",
]
const PANEL_ART: Dictionary[String, String] = {
	"NormalTexture": "Interface\\Glues\\Common\\Glue-Panel-Button-Up",
	"PushedTexture": "Interface\\Glues\\Common\\Glue-Panel-Button-Down",
	"HighlightTexture": "Interface\\Glues\\Common\\Glue-Panel-Button-Highlight",
}
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
# RACE_ICON_TCOORDS as cells of the race icon sheet; female icons sit two rows lower.
const RACE_ICON_CELLS: Dictionary[String, Vector2i] = {
	"Human": Vector2i(0, 0), "Dwarf": Vector2i(1, 0), "Gnome": Vector2i(2, 0),
	"NightElf": Vector2i(3, 0), "Draenei": Vector2i(4, 0), "Tauren": Vector2i(0, 1),
	"Scourge": Vector2i(1, 1), "Troll": Vector2i(2, 1), "Orc": Vector2i(3, 1),
	"BloodElf": Vector2i(4, 1),
}
const RACE_ICON_ROW: float = 0.25
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
	"DEATHKNIGHT": Rect2(0.25, 0.5, 0.24609375, 0.25),
}
const GENDER_ICON_RECTS: Array[Rect2] = [Rect2(0.0, 0.0, 0.5, 1.0), Rect2(0.5, 0.0, 0.5, 1.0)]
const FACTION_ICON_RECTS: Array[Rect2] = [Rect2(0.0, 0.0, 0.5, 1.0), Rect2(0.5, 0.0, 0.5, 1.0)]
const FACTION_KEYS: Array[String] = ["ALLIANCE", "HORDE"]
# FACTION_BACKDROP_COLOR_TABLE: the info panels' background by faction.
const FACTION_BACKGROUNDS: Array[Color] = [Color(0.09, 0.09, 0.19), Color(0.19, 0.05, 0.05)]
const NAME_BORDER: Color = Color(0.5, 0.5, 0.5)
const LOCKED_TINT: Color = Color(0.4, 0.4, 0.4)
# FontStrings in the info panels hang two units under the one above them.
const TEXT_GAP: float = 2.0
const INITIAL_FACING: float = -15.0
const DRAG_DEGREES_PER_PIXEL: float = 0.6
const ROTATE_DEGREES_PER_SECOND: float = 120.0

var _look: Dictionary = {}
# The highest level on the account, which 3.3.5 gates the Death Knight behind.
var max_level: int = 0
var _service: Service = Service.NONE
# The existing character a paid service reshapes, as the character list gave it.
var _customizing: Dictionary = {}
var _classes: Array[int] = []
var _class_id: int = 0
var _race_buttons: Array[WowButton] = []
var _class_buttons: Array[WowButton] = []
var _gender_buttons: Array[WowButton] = []

# 3.3.5 dropped the faction info panel for headings over the two race columns.
@onready var _faction_panel: Control = get_node_or_null("%CharacterCreateCharacterFaction")
@onready var _model: WowModelFrame = %CharacterCreateModel
@onready var _name_edit: LineEdit = %CharacterCreateNameEdit
@onready var _rotate_left: BaseButton = %CharacterCreateRotateLeft
@onready var _rotate_right: BaseButton = %CharacterCreateRotateRight


func _ready() -> void:
	var order: Array[int] = CharacterOptions.race_order()
	for i: int in order.size():
		var button: WowButton = get_node("%%CharacterCreateRaceButton%d" % (i + 1))
		_race_buttons.append(button)
		button.pressed.connect(_choose_race.bind(order[i]))
		_name_on_hover(button, func() -> String: return CharacterOptions.race_name(order[i]))
	# The screen carries a button per class the expansion has, and shows the race's own.
	while get_node_or_null("%%CharacterCreateClassButton%d" % (_class_buttons.size() + 1)) != null:
		var index: int = _class_buttons.size()
		var button: WowButton = get_node("%%CharacterCreateClassButton%d" % (index + 1))
		_class_buttons.append(button)
		button.pressed.connect(_choose_class.bind(index))
		_name_on_hover(button, func() -> String:
			return CharacterOptions.class_label(_classes[index]) if index < _classes.size() else ""
		)
	_gender_buttons.assign([%CharacterCreateGenderButtonMale, %CharacterCreateGenderButtonFemale])
	for gender: int in _gender_buttons.size():
		var icon: TextureRect = _gender_buttons[gender].get_node("NormalTexture")
		_set_tex_coords(icon, GENDER_ICON_RECTS[gender])
		_gender_buttons[gender].pressed.connect(_choose_gender.bind(gender))
		_name_on_hover(_gender_buttons[gender], func() -> String:
			return WowStrings.get_text(["MALE", "FEMALE"][gender])
		)
	for i: int in CUSTOMIZATIONS.size():
		var frame: String = "%%CharacterCustomizationButtonFrame%d" % (i + 1)
		(get_node(frame + "Text") as Label).text = WowStrings.get_text(
			"CHAR_CUSTOMIZATION%d_DESC" % (i + 1)
		)
		var left: BaseButton = get_node(frame + "LeftButton")
		var right: BaseButton = get_node(frame + "RightButton")
		left.pressed.connect(_cycle.bind(CUSTOMIZATIONS[i], -1))
		right.pressed.connect(_cycle.bind(CUSTOMIZATIONS[i], 1))
	for label_name: String in [
		"CharacterCreateFactionText", "CharacterCreateRaceText",
		"CharacterCreateRaceAbilityText", "CharacterCreateClassText",
	]:
		var label: Label = get_node_or_null("%" + label_name) as Label
		if label != null:
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


# CustomizeExistingCharacter: the next showing starts from this character instead of a new one.
func customize(character: Dictionary, service: Service) -> void:
	_customizing = character
	_service = service


# CharacterCreate_OnShow: a random race and look, the race's first class and a blank name.
func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_service = Service.NONE
		return
	if _service != Service.NONE:
		_show_existing()
		return
	_look = {"gender": randi_range(0, 1)}
	_name_edit.text = ""
	for button: WowButton in _race_buttons + _class_buttons:
		_lock(button, false)
	_choose_race(CharacterOptions.race_order().pick_random())
	_name_edit.grab_focus.call_deferred()


# The service's character with its look, the races the service allows and its class locked.
func _show_existing() -> void:
	var race: int = _customizing["race"]
	var faction: CharacterOptions.Faction = CharacterOptions.faction(race)
	var order: Array[int] = CharacterOptions.race_order()
	for i: int in _race_buttons.size():
		var other: int = order[i]
		var allowed: bool = other == race
		if _service == Service.RACE_CHANGE:
			allowed = CharacterOptions.faction(other) == faction
		elif _service == Service.FACTION_CHANGE:
			allowed = CharacterOptions.faction(other) != faction
		_lock(_race_buttons[i], not allowed \
				or _customizing["class"] not in CharacterOptions.classes_for(other))
	for button: WowButton in _class_buttons:
		_lock(button, true)
	_name_edit.text = _customizing["name"]
	_look = {"gender": _customizing["gender"]}
	_choose_race(race)
	for key: String in OPTION_KEYS.values():
		_look[key] = _customizing.get(key, 0)
	_show_character()


func _choose_race(race: int) -> void:
	_look["race"] = race
	_randomize_look()
	var faction: CharacterOptions.Faction = CharacterOptions.faction(race)
	if _faction_panel != null:
		_set_tex_coords(%CharacterCreateFactionIcon, FACTION_ICON_RECTS[faction])
		%CharacterCreateFactionLabel.text = WowStrings.get_text(FACTION_KEYS[faction])
		%CharacterCreateFactionText.text = WowStrings.get_text(
			"FACTION_INFO_" + FACTION_KEYS[faction]
		)
	var file: String = CharacterOptions.race_file(race).to_upper()
	%CharacterCreateRaceLabel.text = CharacterOptions.race_name(race)
	%CharacterCreateRaceText.text = WowStrings.get_text("RACE_INFO_" + file)
	var abilities: PackedStringArray = []
	while WowStrings.get_text("ABILITY_INFO_%s%d" % [file, abilities.size() + 1], "-") != "-":
		abilities.append(WowStrings.get_text("ABILITY_INFO_%s%d" % [file, abilities.size() + 1]))
	%CharacterCreateRaceAbilityText.text = "\n\n".join(abilities)
	for panel: Control in _panels():
		(panel.get_node("Backdrop") as WowBackdrop).background_color = FACTION_BACKGROUNDS[faction]
	CharacterOptions.apply_scene(_model, race)
	_classes = CharacterOptions.classes_for(race)
	if max_level < DEATH_KNIGHT_LEVEL and _service == Service.NONE:
		_classes.erase(DEATH_KNIGHT)
	for i: int in _class_buttons.size():
		_class_buttons[i].visible = i < _classes.size()
		if _class_buttons[i].visible:
			_set_button_icon(_class_buttons[i], _class_icon(CharacterOptions.class_file(_classes[i])))
	var kept: int = _classes.find(_customizing.get("class", 0)) if _service != Service.NONE else -1
	_choose_class(maxi(kept, 0))
	_refresh_gender()
	_model.facing = INITIAL_FACING
	_stack_texts()


# A race or class a paid service keeps fixed shows dimmed, as the stock disabled buttons are.
func _lock(button: WowButton, locked: bool) -> void:
	button.disabled = locked
	button.modulate = LOCKED_TINT if locked else Color.WHITE


func _choose_class(index: int) -> void:
	_class_id = _classes[index]
	for i: int in _class_buttons.size():
		_mark(_class_buttons[i], i == index, CharacterOptions.class_label(_class_id))
	var class_file: String = CharacterOptions.class_file(_class_id)
	_set_tex_coords(%CharacterCreateClassIcon, _class_icon(class_file))
	%CharacterCreateClassLabel.text = CharacterOptions.class_label(_class_id)
	_swap_panel_art(_class_id == DEATH_KNIGHT)
	%CharacterCreateClassText.text = WowStrings.get_text("CLASS_" + class_file)
	_show_character()
	_stack_texts()


func _choose_gender(gender: int) -> void:
	_look["gender"] = gender
	_randomize_look()
	_refresh_gender()


# Race icons change with gender, and so does what the facial hair option is called.
func _refresh_gender() -> void:
	var race: int = _look["race"]
	var gender: CharacterOptions.Gender = _look["gender"]
	var order: Array[int] = CharacterOptions.race_order()
	for i: int in _race_buttons.size():
		var shown_race: int = order[i]
		_set_button_icon(_race_buttons[i], _race_icon(shown_race, gender))
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
	var look: Dictionary = _look.duplicate()
	look["class"] = _class_id
	_model.show_character(
		CharacterOptions.character_model(CharacterModels.starting_look(look))
	)


func _accept() -> void:
	var character: Dictionary = _look.duplicate()
	character["name"] = _name_edit.text.strip_edges()
	character["class"] = _class_id
	if _service != Service.NONE:
		character["guid"] = _customizing["guid"]
		service_accepted.emit(character, _service)
		return
	create_requested.emit(character)


func _race_icon(race: int, gender: CharacterOptions.Gender) -> Rect2:
	var cell: Vector2i = RACE_ICON_CELLS[CharacterOptions.race_file(race)]
	var row: int = cell.y + (2 if gender == CharacterOptions.Gender.FEMALE else 0)
	var column: float = CharacterOptions.race_icon_column()
	return Rect2(Vector2(cell.x * column, row * RACE_ICON_ROW), Vector2(column, RACE_ICON_ROW))


# The screen's info panels, of which 3.3.5 keeps the race and class ones.
func _panels() -> Array[Control]:
	var panels: Array[Control] = [%CharacterCreateCharacterRace, %CharacterCreateCharacterClass]
	if _faction_panel != null:
		panels.append(_faction_panel)
	return panels


# SetChecked and LockHighlight on the chosen button, with its name shown under it.
# CharacterCreateRaceButton_OnEnter: the button under the cursor names itself, as the chosen one does.
func _name_on_hover(button: WowButton, label: Callable) -> void:
	var text: Label = _highlight_text(button)
	if text == null:
		return
	button.mouse_entered.connect(func() -> void: text.text = label.call())
	button.mouse_exited.connect(func() -> void:
		if not button.checked:
			text.text = ""
	)


# 3.3.5a names the chosen race and class elsewhere, so its buttons carry no label of their own.
func _highlight_text(button: WowButton) -> Label:
	return get_node_or_null("%" + button.name + "HighlightText") as Label


# CharacterCreate_DeathKnightSwap: the panel buttons turn blue while a Death Knight is chosen.
func _swap_panel_art(blue: bool) -> void:
	for button_name: String in PANEL_BUTTONS:
		var button: Control = get_node("%" + button_name)
		for state: String in PANEL_ART:
			var rect: TextureRect = button.get_node_or_null(state)
			if rect == null or not rect.texture is AtlasTexture:
				continue
			var atlas: AtlasTexture = rect.texture.duplicate()
			var art: WowTexture = WowTexture.new()
			art.file = PANEL_ART[state] + ("-Blue.blp" if blue else ".blp")
			atlas.atlas = art
			rect.texture = atlas


func _mark(button: WowButton, chosen: bool, label: String) -> void:
	button.checked = chosen
	button.highlight_locked = chosen
	var text: Label = _highlight_text(button)
	if text != null:
		text.text = label if chosen else ""


# The info texts anchor to the bottom of the text above, which only exists once they are wrapped.
func _stack_texts() -> void:
	var columns: Array[Array] = [
		[%CharacterCreateRaceLabel, %CharacterCreateRaceText, %CharacterCreateRaceAbilityText],
		[%CharacterCreateClassLabel, %CharacterCreateClassText],
	]
	var scrolls: Array[WowScrollFrame] = [
		%CharacterCreateRaceScrollFrame, %CharacterCreateClassScrollFrame,
	]
	if _faction_panel != null:
		columns.append([%CharacterCreateFactionLabel, %CharacterCreateFactionText])
		scrolls.append(%CharacterCreateFactionScrollFrame)
	for column: Array in columns:
		for i: int in range(1, column.size()):
			var above: Label = column[i - 1]
			var below: Label = column[i]
			below.position.y = above.position.y + above.get_minimum_size().y + TEXT_GAP
	for scroll: WowScrollFrame in scrolls:
		scroll.refresh()


# WoW's SetTexCoord: the region, in 0..1 of the texture, that the rect shows.
# The 1.12 atlas has no Death Knight cell, so a class it does not know draws nothing.
func _class_icon(class_file: String) -> Rect2:
	return CLASS_ICON_RECTS.get(class_file, Rect2())


# The pushed art shares the icon sheet, so it takes the same cell as the normal art.
func _set_button_icon(button: WowButton, region: Rect2) -> void:
	for state: String in ["NormalTexture", "PushedTexture"]:
		var rect: TextureRect = button.get_node_or_null(state)
		if rect != null:
			_set_tex_coords(rect, region)


func _set_tex_coords(rect: TextureRect, region: Rect2) -> void:
	var atlas: AtlasTexture = rect.texture as AtlasTexture
	if atlas == null:
		atlas = AtlasTexture.new()
		atlas.atlas = rect.texture
		rect.texture = atlas
	var atlas_size: Vector2 = atlas.atlas.get_size()
	atlas.region = Rect2(region.position * atlas_size, region.size * atlas_size)


func _on_drag(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_model.facing += motion.relative.x * DRAG_DEGREES_PER_PIXEL
