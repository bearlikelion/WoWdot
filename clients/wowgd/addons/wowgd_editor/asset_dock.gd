@tool
class_name WowAssetDock
extends VBoxContainer

signal asset_chosen(path: String)

const MAX_RESULTS: int = 2000

var _all: PackedStringArray = []

@onready var _filter: LineEdit = %Filter
@onready var _files: ItemList = %Files
@onready var _add_button: Button = %AddButton
@onready var _count: Label = %Count


func _ready() -> void:
	_filter.text_changed.connect(_on_filter_changed)
	_files.item_activated.connect(_on_item_activated)
	_add_button.pressed.connect(_on_add_pressed)


func _on_filter_changed(text: String) -> void:
	if _all.is_empty():
		_all = _list_models()
	_files.clear()
	var needle: String = text.to_lower()
	if needle.length() < 3:
		_count.text = "Type 3+ characters"
		return
	var shown: int = 0
	for path: String in _all:
		if not path.to_lower().contains(needle):
			continue
		_files.add_item(path)
		shown += 1
		if shown >= MAX_RESULTS:
			break
	_count.text = "%d shown" % shown


func _on_item_activated(index: int) -> void:
	asset_chosen.emit(_files.get_item_text(index))


func _on_add_pressed() -> void:
	for index: int in _files.get_selected_items():
		asset_chosen.emit(_files.get_item_text(index))


# WMO group files (name_000.wmo) are parts of their root, so only roots are listed.
func _list_models() -> PackedStringArray:
	var result: PackedStringArray = []
	var group_suffix: RegEx = RegEx.create_from_string("_\\d{3}\\.wmo$")
	for path: String in WowAssets.archive.find("*"):
		var lower: String = path.to_lower()
		if lower.get_extension() in ["m2", "wmo"] and group_suffix.search(lower) == null:
			result.append(path)
	return result
