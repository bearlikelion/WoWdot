class_name MacroFrame
extends Control

signal close_requested
signal open_requested

# The stock popup tucks this far under the frame's right edge.
const POPUP_OVERLAP: float = 30.0

# The name and icon chooser, a sibling panel that opens against this frame's right edge.
@export var popup: MacroPopupFrame

var _selected: int = 0
# Whether the character's own macros are on show, the second tab, and not the account's.
var _of_character: bool = false

@onready var _body: TextEdit = %MacroFrameText


func _ready() -> void:
	for slot: int in Macros.MAX_MACROS:
		var button: WowButton = _button(slot)
		button.pressed.connect(_on_macro_pressed.bind(slot))
		button.set_drag_forwarding(_drag_macro.bind(slot), Callable(), Callable())
	%MacroFrameTab1.pressed.connect(_show_set.bind(false))
	%MacroFrameTab2.pressed.connect(_show_set.bind(true))
	%MacroNewButton.pressed.connect(_on_new_pressed)
	%MacroEditButton.pressed.connect(_on_edit_pressed)
	%MacroDeleteButton.pressed.connect(_on_delete_pressed)
	%MacroExitButton.pressed.connect(close_requested.emit)
	%MacroFrameCloseButton.pressed.connect(close_requested.emit)
	%MacroFrameTextButton.pressed.connect(_body.grab_focus)
	_body.text_changed.connect(_on_body_changed)
	_body.theme_type_variation = &"MacroBody"
	%MacroDeleteButtonText.text = WowStrings.get_text("DELETE")
	popup.confirmed.connect(_on_popup_confirmed)
	popup.hide()
	WowClient.macros.changed.connect(refresh)
	visibility_changed.connect(refresh)


func open() -> void:
	open_requested.emit()
	refresh()


func refresh() -> void:
	if not is_visible_in_tree():
		popup.hide()
		return
	var macros: Macros = WowClient.macros
	var session: WowSession = WowClient.session
	%MacroFrameTab1Text.text = WowStrings.get_text("GENERAL_MACROS")
	%MacroFrameTab2Text.text = WowStrings.get_text("CHARACTER_SPECIFIC_MACROS") \
	% session.get_object_name(session.get_player_guid())
	var ids: Array[int] = macros.ids(_of_character)
	if not ids.has(_selected):
		_selected = ids[0] if not ids.is_empty() else 0
	for slot: int in Macros.MAX_MACROS:
		var button: WowButton = _button(slot)
		var id: int = ids[slot] if slot < ids.size() else 0
		var info: Dictionary = macros.info(id)
		button.disabled = id == 0
		button.checked = id != 0 and id == _selected
		(button.get_node("NormalTexture") as TextureRect).texture = _icon(info.get("icon", ""))
		(get_node("%%MacroButton%dName" % (slot + 1)) as Label).text = info.get("name", "")
	var chosen: Dictionary = macros.info(_selected)
	var has_macro: bool = not chosen.is_empty()
	for shown: CanvasItem in [
		%MacroFrameSelectedMacroButton, %MacroFrameSelectedMacroName, %MacroFrameSelectedMacroBackground,
		%MacroFrameEnterMacroText, %MacroFrameCharLimitText, %MacroFrameScrollFrame,
		%MacroFrameTextBackground, %MacroEditButton, %MacroDeleteButton,
	]:
		shown.visible = has_macro
	(%MacroNewButton as BaseButton).disabled = ids.size() >= Macros.MAX_MACROS
	if not has_macro:
		return
	%MacroFrameSelectedMacroName.text = chosen["name"]
	var selected_icon: TextureRect = %MacroFrameSelectedMacroButton.get_node("NormalTexture")
	selected_icon.texture = _icon(chosen["icon"])
	if _body.text != chosen["body"]:
		_body.text = chosen["body"]
	_update_limit()


func _show_set(of_character: bool) -> void:
	_of_character = of_character
	_selected = 0
	popup.hide()
	refresh()


func _update_limit() -> void:
	%MacroFrameCharLimitText.text = WowStrings.get_text("MACROFRAME_CHAR_LIMIT") % _body.text.length()


func _icon(path: String) -> WowTexture:
	if path.is_empty():
		return null
	return WowAssets.spells.icon_texture(path)


func _button(slot: int) -> WowButton:
	return get_node("%%MacroButton%d" % (slot + 1))


func _id_at(slot: int) -> int:
	var ids: Array[int] = WowClient.macros.ids(_of_character)
	return ids[slot] if slot < ids.size() else 0


# PickupMacro: a macro dragged off its button can be dropped on an action bar slot.
func _drag_macro(_at_position: Vector2, slot: int) -> Variant:
	var id: int = _id_at(slot)
	if id == 0:
		return null
	var preview: TextureRect = TextureRect.new()
	preview.texture = _icon(WowClient.macros.info(id)["icon"])
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = _button(slot).size
	set_drag_preview(preview)
	return {"macro": id}


func _on_macro_pressed(slot: int) -> void:
	_selected = _id_at(slot)
	popup.hide()
	refresh()


func _on_new_pressed() -> void:
	_place_popup()
	popup.open(0, "", "")


func _on_edit_pressed() -> void:
	var chosen: Dictionary = WowClient.macros.info(_selected)
	_place_popup()
	popup.open(_selected, chosen["name"], chosen["icon"])


func _place_popup() -> void:
	popup.position = position + Vector2(size.x - POPUP_OVERLAP, 0.0)


func _on_delete_pressed() -> void:
	WowClient.macros.delete(_selected)


func _on_popup_confirmed(id: int, macro_name: String, icon: String) -> void:
	if id == 0:
		_selected = WowClient.macros.create(macro_name, icon, _of_character)
		_body.grab_focus.call_deferred()
	else:
		WowClient.macros.edit(id, macro_name, icon)
	refresh()


func _on_body_changed() -> void:
	if _body.text.length() > Macros.MAX_BODY:
		_body.text = _body.text.left(Macros.MAX_BODY)
		_body.set_caret_line(_body.get_line_count() - 1)
		_body.set_caret_column(_body.get_line(_body.get_line_count() - 1).length())
	WowClient.macros.set_body(_selected, _body.text)
	_update_limit()
