class_name CharacterSelect
extends Control

signal character_chosen(character: Dictionary)
signal create_requested
signal delete_requested(guid: int)
signal realm_change_requested
signal back_requested

const MAX_CHARACTERS: int = 10
const CHARACTER_FLAG_GHOST: int = 0x2000
# CHARACTER_ROTATION_CONSTANT, and CHARACTER_FACING_INCREMENT at the stock 60 updates a second.
const DRAG_DEGREES_PER_PIXEL: float = 0.6
const ROTATE_DEGREES_PER_SECOND: float = 120.0
# CharacterSelect_OnLoad colours the character list with DEFAULT_TOOLTIP_COLOR.
const LIST_BORDER: Color = Color(0.8, 0.8, 0.8)
const LIST_BACKGROUND: Color = Color(0.09, 0.09, 0.09, 0.85)
# The select screen shows the orc scene until a character picks its own.
const DEFAULT_RACE: int = 2
# CharacterDeleteDialog_OnShow: gaps above, between and below the text, box and buttons.
const DELETE_PAD: float = 16.0
const DELETE_TEXT_GAP: float = 20.0
const DELETE_BOX_GAP: float = 5.0
const DELETE_BUTTON_GAP: float = 8.0

var _characters: Array = []
var _selected: int = -1
var _buttons: Array[WowButton] = []

@onready var _model: WowModelFrame = %CharacterSelectModel
@onready var _enter: BaseButton = %CharSelectEnterWorldButton
@onready var _delete: BaseButton = %CharacterSelectDeleteButton
@onready var _create: BaseButton = %CharSelectCreateCharacterButton
@onready var _rotate_left: BaseButton = %CharacterSelectRotateLeft
@onready var _rotate_right: BaseButton = %CharacterSelectRotateRight
@onready var _delete_dialog: Control = %CharacterDeleteDialog
@onready var _delete_background: Control = %CharacterDeleteBackground
@onready var _delete_text: Label = %CharacterDeleteText1
@onready var _delete_hint: Label = %CharacterDeleteText2
@onready var _delete_edit: LineEdit = %CharacterDeleteEditBox
@onready var _delete_confirm: BaseButton = %CharacterDeleteButton1
@onready var _delete_cancel: BaseButton = %CharacterDeleteButton2


func _ready() -> void:
	var backdrop: WowBackdrop = %CharacterSelectCharacterFrame.get_node("Backdrop")
	backdrop.border_color = LIST_BORDER
	backdrop.background_color = LIST_BACKGROUND
	for i: int in MAX_CHARACTERS:
		var button: WowButton = get_node("%%CharSelectCharacterButton%d" % (i + 1))
		_buttons.append(button)
		button.pressed.connect(select.bind(i))
		button.gui_input.connect(_on_button_input.bind(i))
	_enter.pressed.connect(enter_world)
	_create.pressed.connect(create_requested.emit)
	_delete.pressed.connect(_open_delete_dialog)
	%CharSelectChangeRealmButton.pressed.connect(realm_change_requested.emit)
	%CharacterSelectBackButton.pressed.connect(back_requested.emit)
	%CharacterSelectUI.gui_input.connect(_on_drag)
	_delete_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_delete_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_delete_edit.text_changed.connect(_on_delete_text_changed)
	_delete_edit.text_submitted.connect(func(_text: String) -> void: _confirm_delete())
	_delete_confirm.pressed.connect(_confirm_delete)
	_delete_cancel.pressed.connect(_delete_dialog.hide)
	CharacterOptions.apply_scene(_model, DEFAULT_RACE)


func _process(delta: float) -> void:
	var turn: float = float(_rotate_right.button_pressed) - float(_rotate_left.button_pressed)
	if turn != 0.0:
		_model.facing += turn * ROTATE_DEGREES_PER_SECOND * delta


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _delete_dialog.visible:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_delete_dialog.hide()
		return
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
	elif event.is_action_pressed("ui_accept"):
		enter_world()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left"):
		_step(-1)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right"):
		_step(1)
	else:
		return
	get_viewport().set_input_as_handled()


# The guid picks the character to select, such as one just created; 0 keeps the current one.
func show_characters(characters: Array, realm_label: String, select_guid: int = 0) -> void:
	_characters = characters.slice(0, MAX_CHARACTERS)
	%CharSelectRealmName.text = realm_label
	for i: int in MAX_CHARACTERS:
		_buttons[i].visible = i < _characters.size()
		if _buttons[i].visible:
			_fill_button(i, _characters[i])
	_create.visible = _characters.size() < MAX_CHARACTERS
	_enter.disabled = _characters.is_empty()
	_delete.disabled = _characters.is_empty()
	var index: int = clampi(_selected, 0, _characters.size() - 1)
	for i: int in _characters.size():
		if _characters[i]["guid"] == select_guid:
			index = i
	select(index)


func select(index: int) -> void:
	_selected = index
	for i: int in _buttons.size():
		_buttons[i].highlight_locked = i == index
	if index < 0 or index >= _characters.size():
		%CharSelectCharacterName.text = ""
		_model.show_character(null)
		return
	var character: Dictionary = _characters[index]
	%CharSelectCharacterName.text = character["name"]
	CharacterOptions.apply_scene(_model, character["race"])
	_model.facing = 0.0
	_model.show_character(CharacterOptions.character_model(CharacterModels.listed_look(character)))


func enter_world() -> void:
	if _selected >= 0 and _selected < _characters.size():
		character_chosen.emit(_characters[_selected])


func _fill_button(index: int, character: Dictionary) -> void:
	var prefix: String = "%%CharSelectCharacterButton%dButtonText" % (index + 1)
	var info_key: String = "CHARACTER_SELECT_INFO_GHOST" \
	if character.get("flags", 0) & CHARACTER_FLAG_GHOST else "CHARACTER_SELECT_INFO"
	(get_node(prefix + "Name") as Label).text = character["name"]
	(get_node(prefix + "Info") as Label).text = WowStrings.get_text(info_key) % [
		character["level"], CharacterOptions.class_label(character["class"]),
	]
	(get_node(prefix + "Location") as Label).text = AreaInfo.area_name(character["zone"])


func _step(direction: int) -> void:
	if _characters.size() > 1:
		select(posmod(_selected + direction, _characters.size()))


func _open_delete_dialog() -> void:
	if _selected < 0 or _selected >= _characters.size():
		return
	var character: Dictionary = _characters[_selected]
	var confirm: String = WowStrings.get_text("CONFIRM_CHAR_DELETE") % [
		character["name"], character["level"], CharacterOptions.class_label(character["class"]),
	]
	_delete_text.text = WowStrings.strip_colors(confirm)
	_delete_edit.text = ""
	_delete_confirm.disabled = true
	_delete_dialog.show()
	_fit_delete_dialog()
	_delete_edit.grab_focus()


# CharacterDeleteDialog_OnShow sizes the box around its text; the edit box hangs below the hint.
func _fit_delete_dialog() -> void:
	var text_height: float = _delete_text.get_minimum_size().y
	var hint_height: float = _delete_hint.get_minimum_size().y
	var height: float = DELETE_PAD + text_height + hint_height + DELETE_TEXT_GAP + DELETE_BOX_GAP \
	+ _delete_edit.size.y + DELETE_BUTTON_GAP + _delete_confirm.size.y + DELETE_PAD
	_delete_background.offset_top = -height / 2.0
	_delete_background.offset_bottom = height / 2.0
	_delete_text.size.y = text_height
	_delete_hint.position.y = DELETE_PAD + text_height + DELETE_TEXT_GAP
	# The edit box is the dialog's child, not the background's, so it is placed in dialog space.
	_delete_edit.position.y = _delete_background.position.y + _delete_hint.position.y \
	+ hint_height + DELETE_BOX_GAP
	var button_top: float = height - DELETE_PAD - _delete_confirm.size.y
	_delete_confirm.position.y = button_top
	_delete_cancel.position.y = button_top


func _on_delete_text_changed(text: String) -> void:
	var confirm: String = WowStrings.get_text("DELETE_CONFIRM_STRING")
	_delete_confirm.disabled = text.to_upper() != confirm.to_upper()


func _confirm_delete() -> void:
	if _delete_confirm.disabled:
		return
	_delete_dialog.hide()
	delete_requested.emit(_characters[_selected]["guid"])


func _on_button_input(event: InputEvent, index: int) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click and click.double_click and click.button_index == MOUSE_BUTTON_LEFT:
		select(index)
		enter_world()


func _on_drag(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_model.facing += motion.relative.x * DRAG_DEGREES_PER_PIXEL
