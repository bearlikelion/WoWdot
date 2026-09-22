class_name MacroPopupFrame
extends Control

# The macro's id, or 0 for a new one, with the name and icon chosen for it.
signal confirmed(id: int, macro_name: String, icon: String)

const ICONS_SHOWN: int = 20
const ICONS_PER_ROW: int = 5
const ICON_ROWS: int = 4
const ICON_ROW_HEIGHT: float = 36.0
const ICONS: String = "Interface\\Icons\\*.blp"

static var _icons: PackedStringArray = []

var _id: int = 0
var _icon: String = ""
var _offset: int = 0

@onready var _name: LineEdit = %MacroPopupEditBox
@onready var _okay: BaseButton = %MacroPopupOkayButton
@onready var _scroll: WowScrollFrame = %MacroPopupScrollFrame


func _ready() -> void:
	for i: int in ICONS_SHOWN:
		_button(i).pressed.connect(_on_icon_pressed.bind(i))
	_name.text_changed.connect(func(_text: String) -> void: _update())
	_okay.pressed.connect(_on_okay_pressed)
	%MacroPopupCancelButton.pressed.connect(hide)
	_scroll.faux = true
	_scroll.scrolled.connect(_on_scrolled)


func open(id: int, macro_name: String, icon: String) -> void:
	if _icons.is_empty():
		for file: String in WowAssets.archive.find(ICONS):
			_icons.append(file.get_basename())
		_icons.sort()
	_id = id
	_icon = icon
	_name.text = macro_name
	show()
	_name.grab_focus.call_deferred()
	_scroll.set_range(maxi(ceili(float(_icons.size()) / ICONS_PER_ROW) - ICON_ROWS, 0))
	_update()


func _update() -> void:
	for i: int in ICONS_SHOWN:
		var button: WowButton = _button(i)
		var index: int = _offset * ICONS_PER_ROW + i
		button.visible = index < _icons.size()
		if not button.visible:
			continue
		var texture: TextureRect = button.get_node("NormalTexture")
		texture.texture = WowAssets.spells.icon_texture(_icons[index])
		button.checked = _icons[index] == _icon
	_okay.disabled = _name.text.is_empty() or _icon.is_empty()


func _button(index: int) -> WowButton:
	return get_node("%%MacroPopupButton%d" % (index + 1))


func _on_icon_pressed(index: int) -> void:
	_icon = _icons[_offset * ICONS_PER_ROW + index]
	_update()


func _on_scrolled(value: float) -> void:
	_offset = roundi(value)
	_update()


func _on_okay_pressed() -> void:
	hide()
	confirmed.emit(_id, _name.text, _icon)
