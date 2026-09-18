class_name CharacterSelect
extends Control

signal character_chosen(guid: int)

enum Race { HUMAN = 1, ORC, DWARF, NIGHT_ELF, UNDEAD, TAUREN, GNOME, TROLL }
enum CharacterClass {
	WARRIOR = 1, PALADIN, HUNTER, ROGUE, PRIEST, SHAMAN = 7, MAGE, WARLOCK, DRUID = 11,
}
enum Gender { MALE, FEMALE }

# Picked automatically as soon as the list arrives, for scripted logins.
var preferred_name: String = ""

var _characters: Array = []

@onready var _list: ItemList = %Characters
@onready var _enter_button: Button = %EnterButton
@onready var _create_button: Button = %CreateButton
@onready var _create_panel: Control = %CreatePanel
@onready var _name_edit: LineEdit = %NameEdit
@onready var _race_option: OptionButton = %RaceOption
@onready var _class_option: OptionButton = %ClassOption
@onready var _gender_option: OptionButton = %GenderOption
@onready var _confirm_button: Button = %ConfirmButton
@onready var _status: Label = %Status


func _ready() -> void:
	_fill_option(_race_option, Race)
	_fill_option(_class_option, CharacterClass)
	_fill_option(_gender_option, Gender)
	_enter_button.pressed.connect(_on_enter_pressed)
	_list.item_activated.connect(_on_item_activated)
	_create_button.pressed.connect(_on_create_pressed)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	WowClient.session.characters_received.connect(_on_characters_received)
	WowClient.session.character_created.connect(_on_character_created)


func _on_characters_received(characters: Array) -> void:
	_characters = characters.duplicate()
	_list.clear()
	for character: Dictionary in characters:
		_list.add_item("%s  (level %d)" % [character["name"], character["level"]])
	if not characters.is_empty():
		_list.select(0)
	_create_panel.visible = characters.is_empty()
	for character: Dictionary in characters:
		if character["name"] == preferred_name:
			preferred_name = ""
			character_chosen.emit(character["guid"])


func _on_enter_pressed() -> void:
	var selected: PackedInt32Array = _list.get_selected_items()
	if not selected.is_empty():
		_on_item_activated(selected[0])


func _on_item_activated(index: int) -> void:
	if index < _characters.size():
		character_chosen.emit(_characters[index]["guid"])


func _on_create_pressed() -> void:
	_create_panel.visible = not _create_panel.visible


func _on_confirm_pressed() -> void:
	_status.text = "Creating..."
	WowClient.session.create_character({
		"name": _name_edit.text,
		"race": _race_option.get_selected_id(),
		"class": _class_option.get_selected_id(),
		"gender": _gender_option.get_selected_id(),
	})


func _on_character_created(success: bool, code: int) -> void:
	_status.text = "" if success else "The server refused that character (code %d)." % code
	if success:
		WowClient.session.request_characters()


func _fill_option(option: OptionButton, values: Dictionary) -> void:
	for key: String in values:
		option.add_item(key.capitalize(), values[key])
