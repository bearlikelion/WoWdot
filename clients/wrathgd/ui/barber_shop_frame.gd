class_name BarberShopFrame
extends Control

signal caption_changed(text: String)

enum Selector { HAIR_STYLE, HAIR_COLOR, FACIAL_HAIR }

const BACKGROUND: String = "Interface\\Barbershop\\UI-Barbershop.blp"
# GetBarberShopCost: a new colour on the old style is half price, new facial hair three quarters.
const COLOR_COST: float = 0.5
const FACIAL_HAIR_COST: float = 0.75

# Each selector's choices; hair style and facial hair as BarberShopStyle {id, data, name} rows.
var _styles: Dictionary[Selector, Array] = {}
var _chosen: Dictionary[Selector, int] = {}
var _current: Dictionary[Selector, int] = {}
var _color_count: int = 1

@onready var _barbershop: Barbershop = WowClient.barbershop


func _ready() -> void:
	for selector: Selector in Selector.values():
		var prefix: String = "%%BarberShopFrameSelector%d" % (selector + 1)
		(get_node(prefix + "Prev") as BaseButton).pressed.connect(_step.bind(selector, -1))
		(get_node(prefix + "Next") as BaseButton).pressed.connect(_step.bind(selector, 1))
	%BarberShopFrameSelector4.hide()
	%BarberShopFrameOkayButton.pressed.connect(_on_okay_pressed)
	%BarberShopFrameCancelButton.pressed.connect(_barbershop.leave)
	%BarberShopFrameResetButton.pressed.connect(_reset)
	var background: WowTexture = WowTexture.new()
	background.file = BACKGROUND
	%BarberShopFrameBackground.texture = background
	_barbershop.opened.connect(_on_opened)
	_barbershop.closed.connect(hide)


# BarberShop_OnLoad and _OnShow: the chair's choices start on the player's own look.
func _on_opened() -> void:
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	var look: Dictionary = CharacterModels.player_look(session, guid)
	var race: int = look["race"]
	var gender: int = look["gender"]
	_styles[Selector.HAIR_STYLE] = _style_rows(race, gender, Barbershop.StyleType.HAIR)
	_styles[Selector.FACIAL_HAIR] = _style_rows(race, gender, Barbershop.StyleType.FACIAL_HAIR)
	_color_count = maxi(
		WowAssets.characters.option_count(look, CharacterModels.Option.HAIR_COLOR), 1
	)
	_current[Selector.HAIR_STYLE] = _index_of(Selector.HAIR_STYLE, look["hair_style"])
	_current[Selector.HAIR_COLOR] = look["hair_color"]
	_current[Selector.FACIAL_HAIR] = _index_of(Selector.FACIAL_HAIR, look["facial_hair"])
	var hair_kind: String = CharacterOptions.hair_kind(race)
	(%BarberShopFrameSelector1Category as Label).text = \
			WowStrings.get_text("HAIR_%s_STYLE" % hair_kind)
	(%BarberShopFrameSelector2Category as Label).text = \
			WowStrings.get_text("HAIR_%s_COLOR" % hair_kind)
	(%BarberShopFrameSelector3Category as Label).text = WowStrings.get_text(
		"FACIAL_HAIR_" + CharacterOptions.facial_hair_kind(race, gender as CharacterOptions.Gender)
	)
	show()
	_reset()


func _style_rows(race: int, gender: int, type: Barbershop.StyleType) -> Array[Dictionary]:
	var table: WowDBC = WowDBC.open(WowAssets.archive, "BarberShopStyle")
	var rows: Array[Dictionary] = []
	for row: int in table.row_count():
		if table.get_uint(row, "Type") == type and table.get_uint(row, "Race") == race \
		and table.get_uint(row, "Sex") == gender:
			rows.append({
				"id": table.get_uint(row, "ID"),
				"data": table.get_uint(row, "Data"),
				"name": table.get_string(row, "Name"),
			})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["data"] < b["data"])
	return rows


func _index_of(selector: Selector, data: int) -> int:
	var rows: Array = _styles[selector]
	for i: int in rows.size():
		if rows[i]["data"] == data:
			return i
	return 0


func _reset() -> void:
	_chosen = _current.duplicate()
	caption_changed.emit(WowStrings.get_text("BARBERSHOP"))
	_update()


func _step(selector: Selector, direction: int) -> void:
	var count: int = _color_count if selector == Selector.HAIR_COLOR else _styles[selector].size()
	_chosen[selector] = posmod(_chosen[selector] + direction, maxi(count, 1))
	if selector != Selector.HAIR_COLOR and not _styles[selector].is_empty():
		caption_changed.emit(_styles[selector][_chosen[selector]]["name"])
	_update()


# BarberShop_Update: the preview, the cost and which labels read as changed.
func _update() -> void:
	_barbershop.set_preview({
		"hair_style": _data(Selector.HAIR_STYLE),
		"hair_color": _chosen[Selector.HAIR_COLOR],
		"facial_hair": _data(Selector.FACIAL_HAIR),
	})
	var changed: bool = false
	for selector: Selector in Selector.values():
		var same: bool = _chosen[selector] == _current[selector]
		changed = changed or not same
		var label: Label = get_node("%%BarberShopFrameSelector%dCategory" % (selector + 1))
		label.theme_type_variation = &"GameFontHighlight" if same else &"GameFontNormal"
	(%BarberShopFrameMoneyFrame as MoneyFrame).set_money(_cost())
	%BarberShopFrameOkayButton.disabled = not changed
	%BarberShopFrameResetButton.disabled = not changed


func _data(selector: Selector) -> int:
	var rows: Array = _styles[selector]
	return rows[_chosen[selector]]["data"] if not rows.is_empty() else 0


# GetBarberShopCost against gtBarberShopCostBase for the player's level.
func _cost() -> int:
	var session: WowSession = WowClient.session
	var level: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_LEVEL")
	var table: WowDBC = WowDBC.open(WowAssets.archive, "gtBarberShopCostBase")
	var base: float = table.get_float(clampi(level - 1, 0, table.row_count() - 1), "Cost")
	var cost: float = 0.0
	var style_changed: bool = _chosen[Selector.HAIR_STYLE] != _current[Selector.HAIR_STYLE]
	if style_changed:
		cost += base
	elif _chosen[Selector.HAIR_COLOR] != _current[Selector.HAIR_COLOR]:
		cost += base * COLOR_COST
	if _chosen[Selector.FACIAL_HAIR] != _current[Selector.FACIAL_HAIR]:
		cost += base * FACIAL_HAIR_COST
	return int(cost)


func _on_okay_pressed() -> void:
	var hair: Array = _styles[Selector.HAIR_STYLE]
	var facial: Array = _styles[Selector.FACIAL_HAIR]
	_barbershop.apply(
		hair[_chosen[Selector.HAIR_STYLE]]["id"] if not hair.is_empty() else 0,
		_chosen[Selector.HAIR_COLOR],
		facial[_chosen[Selector.FACIAL_HAIR]]["id"] if not facial.is_empty() else 0,
	)
