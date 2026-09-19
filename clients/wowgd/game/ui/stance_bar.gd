class_name StanceBar
extends Control

# Spell.dbc 1.12 columns: the three effects' aura types, then their misc values.
const EFFECT_AURA_COLUMN: int = 91
const EFFECT_MISC_COLUMN: int = 106
const EFFECT_COUNT: int = 3
const AURA_MOD_SHAPESHIFT: int = 36
const BUTTON_COUNT: int = 10

# Form id and the spell that takes it, ordered by form as ShapeshiftBar_Update reads them.
var _forms: Array[Vector2i] = []
var _buttons: Array[ActionButton] = []


func _ready() -> void:
	for i: int in BUTTON_COUNT:
		var button: ActionButton = get_node("%%ShapeshiftButton%d" % (i + 1))
		button.pressed.connect(_on_button_pressed.bind(i))
		_buttons.append(button)
	var session: WowSession = WowClient.session
	session.spells_changed.connect(_rebuild)
	session.object_updated.connect(_on_object_updated)
	_rebuild()


# ponytail: a druid gets a button per form, where the stock bar merges Bear into Dire Bear.
func _rebuild() -> void:
	var spells: WowDBC = WowDBC.open(WowAssets.archive, "Spell")
	_forms.clear()
	for spell_id: int in WowClient.session.get_known_spells():
		var form: int = _form_of(spells, spell_id)
		if form > 0:
			_forms.append(Vector2i(form, spell_id))
	_forms.sort()
	_refresh()


func _form_of(spells: WowDBC, spell_id: int) -> int:
	var row: int = spells.find(spell_id)
	if row < 0:
		return 0
	for i: int in EFFECT_COUNT:
		if spells.get_uint(row, EFFECT_AURA_COLUMN + i) == AURA_MOD_SHAPESHIFT:
			return spells.get_uint(row, EFFECT_MISC_COLUMN + i)
	return 0


func _refresh() -> void:
	var session: WowSession = WowClient.session
	var form: int = (session.get_field(session.get_player_guid(), "UNIT_FIELD_BYTES_1") >> 16) & 0xFF
	for i: int in BUTTON_COUNT:
		var button: ActionButton = _buttons[i]
		button.visible = i < _forms.size()
		if button.visible:
			button.stance_spell = _forms[i].y
			button.stance_active = _forms[i].x == form
	visible = not _forms.is_empty()


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid():
		_refresh()


func _on_button_pressed(index: int) -> void:
	if index < _forms.size():
		WowClient.session.cast_spell(_forms[index].y)
