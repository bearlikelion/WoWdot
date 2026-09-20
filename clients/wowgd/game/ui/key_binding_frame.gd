class_name KeyBindingFrame
extends Control

signal close_requested

const ROWS: int = 17
const KEY_SLOTS: int = 2
const NOT_BOUND_ALPHA: float = 0.8

# The binding a key press lands on, and which of its two slots.
var _selected_action: String = ""
var _selected_slot: int = 0
# Every binding's keys as the window opened, so Cancel can put them back.
var _opened: Dictionary[String, PackedStringArray] = {}
var _rows: Array[Dictionary] = []
var _accepted: bool = false

@onready var _scroll: WowScrollFrame = %KeyBindingFrameScrollFrame


func _ready() -> void:
	_scroll.faux = true
	_scroll.scrolled.connect(func(_value: float) -> void: _refresh())
	for row: int in ROWS:
		for slot: int in KEY_SLOTS:
			var button: BaseButton = _key_button(row, slot)
			button.pressed.connect(_on_key_pressed.bind(row, slot))
	%KeyBindingFrameUnbindButton.pressed.connect(_on_unbind_pressed)
	%KeyBindingFrameOkayButton.pressed.connect(_on_okay_pressed)
	%KeyBindingFrameCancelButton.pressed.connect(close_requested.emit)
	# One binding set, so the per character choice has nothing to offer.
	(%KeyBindingFrameCharacterButton as BaseButton).disabled = true
	%KeyBindingFrameHeaderText.text = WowStrings.get_text("KEY_BINDINGS")
	visibility_changed.connect(_on_visibility_changed)
	hide()


# A key press lands on the binding waiting for one; Escape drops the selection instead.
func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _selected_action.is_empty():
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	if key.physical_keycode != KEY_ESCAPE:
		KeyBindings.bind(_selected_action, _selected_slot, key.duplicate())
	_selected_action = ""
	_refresh()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		if not _accepted:
			for action: String in _opened:
				KeyBindings.set_keys(action, _opened[action])
		return
	_accepted = false
	_selected_action = ""
	_rows = KeyBindings.listed().filter(_carries_binding)
	_opened.clear()
	for entry: Dictionary in _rows:
		if entry.has("action"):
			_opened[entry["action"]] = _keys_of(entry["action"])
	_scroll.set_range(maxf(_rows.size() - ROWS, 0.0))
	_scroll.scroll_to(0.0)
	_refresh()


# KeyBindingFrame_Update: headers and bindings fill the rows from the scroll position down.
func _refresh() -> void:
	# KeyBindingFrame_UpdateUnbindKey: there is nothing to unbind until a binding is picked.
	(%KeyBindingFrameUnbindButton as BaseButton).disabled = _selected_action.is_empty()
	var offset: int = roundi(_scroll.scroll())
	for row: int in ROWS:
		var index: int = offset + row
		var entry: Dictionary = _rows[index] if index < _rows.size() else {}
		var header: Label = get_node("%%KeyBindingFrameBinding%dHeader" % (row + 1))
		var description: Label = get_node("%%KeyBindingFrameBinding%dDescription" % (row + 1))
		var line: Control = get_node("%%KeyBindingFrameBinding%d" % (row + 1))
		line.visible = not entry.is_empty()
		header.visible = entry.has("header")
		description.visible = entry.has("action")
		for slot: int in KEY_SLOTS:
			_key_button(row, slot).visible = entry.has("action")
		if entry.has("header"):
			header.text = WowStrings.get_text("BINDING_HEADER_" + entry["header"])
		elif entry.has("action"):
			description.text = _binding_name(entry)
			for slot: int in KEY_SLOTS:
				var key: String = KeyBindings.binding_text(entry["action"], slot)
				var button: BaseButton = _key_button(row, slot)
				var waiting: bool = entry["action"] == _selected_action and slot == _selected_slot
				_key_label(row, slot).text = key if not key.is_empty() \
				else WowStrings.get_text("NOT_BOUND")
				button.modulate.a = 1.0 if not key.is_empty() else NOT_BOUND_ALPHA
				button.button_pressed = waiting


# A header with no binding under it would sit there naming nothing.
func _carries_binding(entry: Dictionary) -> bool:
	if entry.has("action"):
		return true
	var listed: Array[Dictionary] = KeyBindings.listed()
	var after: int = listed.find(entry) + 1
	return after < listed.size() and listed[after].has("action")


func _binding_name(entry: Dictionary) -> String:
	var stock: String = WowStrings.get_text("BINDING_NAME_" + entry["name"], "")
	return stock if not stock.is_empty() else String(entry["action"]).capitalize()


func _keys_of(action: String) -> PackedStringArray:
	var keys: PackedStringArray = []
	for slot: int in KEY_SLOTS:
		keys.append(KeyBindings.binding_text(action, slot))
	return keys


func _key_button(row: int, slot: int) -> BaseButton:
	return get_node("%%KeyBindingFrameBinding%dKey%dButton" % [row + 1, slot + 1])


func _key_label(row: int, slot: int) -> Label:
	return get_node("%%KeyBindingFrameBinding%dKey%dButtonText" % [row + 1, slot + 1])


func _on_key_pressed(row: int, slot: int) -> void:
	var index: int = roundi(_scroll.scroll()) + row
	if index >= _rows.size() or not _rows[index].has("action"):
		return
	_selected_action = _rows[index]["action"]
	_selected_slot = slot
	_refresh()


func _on_unbind_pressed() -> void:
	if _selected_action.is_empty():
		return
	KeyBindings.unbind(_selected_action, _selected_slot)
	_selected_action = ""
	_refresh()


func _on_okay_pressed() -> void:
	_accepted = true
	KeyBindings.save()
	close_requested.emit()
