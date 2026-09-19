class_name RealmList
extends Control

signal realm_chosen(index: int)
signal cancelled

enum RealmType { NORMAL = 0, PVP = 1, RP = 6, RP_PVP = 8 }

const REALM_FLAG_OFFLINE: int = 0x02
const REALM_FLAG_FULL: int = 0x80
const ROWS: int = 18
const TABS: int = 8
# The row template's OnLoad moves the PVP column, and the columns after it, right of the name.
const COLUMN_SHIFT: float = 235.0
const HIGHLIGHT_WITH_CHARACTERS: Color = Color(0.1, 1.0, 0.1)
const HIGHLIGHT_WITHOUT: Color = Color(1.0, 0.78, 0.0)
# The population the logon server reports: below one is low, above one high.
const POPULATION_MEDIUM: float = 1.0

var _realms: Array = []
var _selected: int = -1
var _rows: Array[BaseButton] = []

@onready var _highlight: Control = %RealmListHighlight
@onready var _ok: BaseButton = %RealmListOkButton


func _ready() -> void:
	for i: int in ROWS:
		var row: BaseButton = get_node("%%RealmListRealmButton%d" % (i + 1))
		_rows.append(row)
		row.pressed.connect(_select.bind(i))
		row.gui_input.connect(_on_row_input.bind(i))
		for column: String in ["PVP", "Players", "Load"]:
			_row_label(row, column).position.x += COLUMN_SHIFT
	# vMaNGOS reports one realm category, so the tabs stay hidden as RealmList_UpdateTabs does.
	for i: int in TABS:
		(get_node("%%RealmListTab%d" % (i + 1)) as CanvasItem).hide()
	%RealmListScrollFrame.hide()
	_ok.pressed.connect(_accept)
	%RealmListCancelButton.pressed.connect(_cancel)
	%RealmListCloseButton.pressed.connect(_cancel)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_cancel()
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_accept()


# ponytail: the first 18 realms only; wire up the scroll frame when a list grows past that.
func open(realms: Array, current_name: String) -> void:
	_realms = realms
	_selected = -1
	for i: int in realms.size():
		if realms[i]["name"] == current_name:
			_selected = i
	_update()
	show()


func _update() -> void:
	for i: int in ROWS:
		var row: BaseButton = _rows[i]
		row.visible = i < _realms.size()
		if not row.visible:
			continue
		var realm: Dictionary = _realms[i]
		var selected: bool = i == _selected
		var offline: bool = realm["flags"] & REALM_FLAG_OFFLINE != 0
		var characters: int = realm["characters"]
		var name_label: Label = _row_label(row, "NormalText")
		name_label.text = realm["name"]
		name_label.theme_type_variation = &"GlueFontDisable" if offline \
		else &"GlueFontHighlight" if selected \
		else &"GlueFontGreen" if characters > 0 else &"GlueFontNormal"
		var type_label: Label = _row_label(row, "PVP")
		match realm["icon"] as RealmType:
			RealmType.PVP:
				type_label.text = WowStrings.get_text("PVP_PARENTHESES")
				type_label.theme_type_variation = &"GlueFontRedSmall"
			RealmType.RP:
				type_label.text = WowStrings.get_text("RP_PARENTHESES")
				type_label.theme_type_variation = &"GlueFontGreenSmall"
			RealmType.RP_PVP:
				type_label.text = WowStrings.get_text("RPPVP_PARENTHESES")
				type_label.theme_type_variation = &"GlueFontNormalSmall"
			_:
				type_label.text = WowStrings.get_text("GAMETYPE_NORMAL")
				type_label.theme_type_variation = &"GlueFontNormalSmall"
		_row_label(row, "Players").text = "(%d)" % characters if characters > 0 else ""
		var load_label: Label = _row_label(row, "Load")
		var population: float = realm["population"]
		if offline:
			load_label.text = WowStrings.get_text("REALM_DOWN")
			load_label.theme_type_variation = &"GlueFontDisableSmall"
		elif realm["flags"] & REALM_FLAG_FULL != 0:
			load_label.text = WowStrings.get_text("LOAD_FULL")
			load_label.theme_type_variation = &"GlueFontRedSmall"
		elif population < POPULATION_MEDIUM:
			load_label.text = WowStrings.get_text("LOAD_LOW")
			load_label.theme_type_variation = &"GlueFontGreenSmall"
		elif population > POPULATION_MEDIUM:
			load_label.text = WowStrings.get_text("LOAD_HIGH")
			load_label.theme_type_variation = &"GlueFontRedSmall"
		else:
			load_label.text = WowStrings.get_text("LOAD_MEDIUM")
			load_label.theme_type_variation = &"GlueFontNormalSmall"
		if selected and not offline:
			type_label.theme_type_variation = &"GlueFontHighlightSmall"
			load_label.theme_type_variation = &"GlueFontHighlightSmall"
		row.disabled = offline
	var usable: bool = _selected >= 0 and _realms[_selected]["flags"] & REALM_FLAG_OFFLINE == 0
	_ok.disabled = not usable
	_highlight.visible = usable
	if usable:
		_highlight.position = _rows[_selected].position
		%RealmListHighlightTexture.self_modulate = HIGHLIGHT_WITH_CHARACTERS \
		if _realms[_selected]["characters"] > 0 else HIGHLIGHT_WITHOUT


func _row_label(row: BaseButton, column: String) -> Label:
	return row.get_node("%%%s%s" % [row.name, column])


func _select(index: int) -> void:
	_selected = index
	_update()


func _accept() -> void:
	if _ok.disabled:
		return
	hide()
	realm_chosen.emit(_selected)


func _cancel() -> void:
	hide()
	cancelled.emit()


func _on_row_input(event: InputEvent, index: int) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click and click.double_click and click.button_index == MOUSE_BUTTON_LEFT:
		_select(index)
		_accept()
