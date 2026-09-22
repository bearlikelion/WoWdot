class_name GearManagerDialog
extends Control

const ICONS_SHOWN: int = 15
const ICONS_PER_ROW: int = 5
const ICON_ROWS: int = 3
const ICONS: String = "Interface\\Icons\\*.blp"
const ICON_PATH: String = "Interface\\Icons\\"

static var _icons: PackedStringArray = []

var _selected: String = ""
var _icon: String = ""
var _offset: int = 0

@onready var _popup: Control = %GearManagerDialogPopup
@onready var _name: LineEdit = %GearManagerDialogPopupEditBox
@onready var _scroll: WowScrollFrame = %GearManagerDialogPopupScrollFrame


func _ready() -> void:
	for i: int in EquipmentSets.MAX_SETS:
		_set_button(i).pressed.connect(_on_set_pressed.bind(i))
	for i: int in ICONS_SHOWN:
		_icon_button(i).pressed.connect(_on_icon_pressed.bind(i))
	($FontString as Label).text = WowStrings.get_text("EQUIPMENT_MANAGER")
	%GearManagerDialogClose.pressed.connect(hide)
	%GearManagerDialogEquipSet.pressed.connect(_on_equip_pressed)
	%GearManagerDialogDeleteSet.pressed.connect(_on_delete_pressed)
	%GearManagerDialogSaveSet.pressed.connect(_open_popup)
	%GearManagerDialogPopupOkay.pressed.connect(_on_okay_pressed)
	%GearManagerDialogPopupCancel.pressed.connect(_popup.hide)
	_name.text_changed.connect(func(_text: String) -> void: _update_popup())
	_scroll.faux = true
	_scroll.scrolled.connect(_on_scrolled)
	WowClient.equipment_sets.changed.connect(refresh)
	visibility_changed.connect(_on_visibility_changed)
	refresh()


func refresh() -> void:
	var sets: Array[Dictionary] = WowClient.equipment_sets.sets
	if WowClient.equipment_sets.find(_selected).is_empty():
		_selected = ""
	for i: int in EquipmentSets.MAX_SETS:
		var button: WowButton = _set_button(i)
		var entry: Dictionary = sets[i] if i < sets.size() else {}
		var icon: TextureRect = button.get_node("NormalTexture")
		icon.texture = null if entry.is_empty() \
				else WowAssets.spells.icon_texture(ICON_PATH + entry["icon"])
		(get_node("%%GearSetButton%dName" % (i + 1)) as Label).text = entry.get("name", "")
		button.disabled = entry.is_empty()
		button.checked = not entry.is_empty() and entry["name"] == _selected
	%GearManagerDialogEquipSet.disabled = _selected.is_empty()
	%GearManagerDialogDeleteSet.disabled = _selected.is_empty()


func _set_button(index: int) -> WowButton:
	return get_node("%%GearSetButton%d" % (index + 1))


func _icon_button(index: int) -> WowButton:
	return get_node("%%GearManagerDialogPopupButton%d" % (index + 1))


func _on_visibility_changed() -> void:
	if not visible:
		_popup.hide()


func _on_set_pressed(index: int) -> void:
	_selected = WowClient.equipment_sets.sets[index]["name"]
	refresh()


func _on_equip_pressed() -> void:
	WowClient.equipment_sets.use(WowClient.equipment_sets.find(_selected))


func _on_delete_pressed() -> void:
	WowClient.equipment_sets.delete(WowClient.equipment_sets.find(_selected))


func _open_popup() -> void:
	if _icons.is_empty():
		for file: String in WowAssets.archive.find(ICONS):
			_icons.append(file.get_file().get_basename())
		_icons.sort()
	var entry: Dictionary = WowClient.equipment_sets.find(_selected)
	_name.text = _selected
	_icon = entry.get("icon", "")
	_popup.show()
	_name.grab_focus.call_deferred()
	_scroll.set_range(maxi(ceili(float(_icons.size()) / ICONS_PER_ROW) - ICON_ROWS, 0))
	_update_popup()


func _update_popup() -> void:
	for i: int in ICONS_SHOWN:
		var button: WowButton = _icon_button(i)
		var index: int = _offset * ICONS_PER_ROW + i
		button.visible = index < _icons.size()
		if not button.visible:
			continue
		var texture: TextureRect = button.get_node("NormalTexture")
		texture.texture = WowAssets.spells.icon_texture(ICON_PATH + _icons[index])
		button.checked = _icons[index] == _icon
	%GearManagerDialogPopupOkay.disabled = _name.text.is_empty() or _icon.is_empty()


func _on_icon_pressed(index: int) -> void:
	_icon = _icons[_offset * ICONS_PER_ROW + index]
	_update_popup()


func _on_scrolled(value: float) -> void:
	_offset = roundi(value)
	_update_popup()


func _on_okay_pressed() -> void:
	_popup.hide()
	_selected = _name.text
	WowClient.equipment_sets.save(_name.text, _icon)
