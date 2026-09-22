class_name ContainerFrame
extends Control

signal closed(bag: int)
signal item_used(bag: int, slot: int)
signal item_hovered(bag: int, slot: int, button: ItemButton)
signal item_left(button: ItemButton)

const COLUMNS: int = 4
const MAX_ITEMS: int = 36
const WIDTH: float = 192.0
const BUTTON_SIZE: float = 37.0
# ContainerFrame_GenerateFrame's spacing between buttons and from the frame's bottom right.
const BUTTON_GAP: Vector2 = Vector2(5.0, 4.0)
const FIRST_BUTTON_INSET: float = 12.0
const BACKPACK_BOTTOM: float = 30.0
const BAG_BOTTOM: float = 9.0
const BACKPACK_HEIGHT: float = 240.0
const ROW_HEIGHT: float = 41.0
const ROWS_IN_BG_TEXTURE: int = 6
const BG_TEXTURE_HEIGHT: float = 512.0
const FIRST_ROW_PIXELS: float = 9.0
const FIRST_ROW_TEXCOORD: float = 0.353515625
const BOTTOM_HEIGHT: float = 10.0
const BACKPACK_BACKGROUND: String = "Interface\\ContainerFrame\\UI-BackpackBackground.blp"
const BAG_BACKGROUND: String = "Interface\\ContainerFrame\\UI-Bag-Components.blp"
const BACKPACK_ICON: String = "Interface\\Buttons\\Button-Backpack-Up.blp"
const KEYRING_ICON: String = "Interface\\ContainerFrame\\KeyRing-Bag-Icon.blp"
const PORTRAIT_SHADER: Shader = preload("res://ui/portrait.gdshader")

var bag: int = -1

var _size: int = 0
var _buttons: Array[ItemButton] = []

@onready var _top: TextureRect = %BackgroundTop
@onready var _middle: TextureRect = %BackgroundMiddle1
@onready var _middle_extra: TextureRect = %BackgroundMiddle2
@onready var _bottom: TextureRect = %BackgroundBottom
@onready var _portrait: TextureRect = %Portrait
@onready var _money: MoneyFrame = %MoneyFrame


func _ready() -> void:
	for i: int in MAX_ITEMS:
		var button: ItemButton = get_node("%%Item%d" % (i + 1))
		_buttons.append(button)
		button.right_clicked.connect(_on_button_used.bind(i))
		button.mouse_entered.connect(_on_button_entered.bind(i))
		button.mouse_exited.connect(func() -> void: item_left.emit(button))
	%CloseButton.pressed.connect(close)
	var portrait_material: ShaderMaterial = ShaderMaterial.new()
	portrait_material.shader = PORTRAIT_SHADER
	_portrait.material = portrait_material


# ContainerFrame_GenerateFrame: backgrounds and buttons for this many slots, then the items.
func open(bag_id: int) -> void:
	bag = bag_id
	_size = Inventory.container_size(bag)
	var rows: int = ceili(_size / float(COLUMNS))
	var height: float = BACKPACK_HEIGHT
	_middle.hide()
	_middle_extra.hide()
	_bottom.hide()
	_money.visible = bag == Inventory.BACKPACK
	if bag == Inventory.BACKPACK:
		_set_texture(_top, BACKPACK_BACKGROUND, 0.0, 1.0)
		_top.size.y = 256.0
	else:
		height = _layout_bag_background(rows)
	size = Vector2(WIDTH, height)
	for rect: TextureRect in [_top, _middle, _middle_extra, _bottom]:
		rect.position.x = WIDTH - rect.size.x
	var bottom_inset: float = BACKPACK_BOTTOM if bag == Inventory.BACKPACK else BAG_BOTTOM
	for j: int in _buttons.size():
		var button: ItemButton = _buttons[j]
		button.visible = j < _size
		button.address = Inventory.wire_address(bag, _slot(j)) if j < _size else -Vector2i.ONE
		var column: int = j % COLUMNS
		var row: int = floori(j / float(COLUMNS))
		button.position = Vector2(
			WIDTH - FIRST_BUTTON_INSET - BUTTON_SIZE - column * (BUTTON_SIZE + BUTTON_GAP.x),
			height - bottom_inset - BUTTON_SIZE - row * (BUTTON_SIZE + BUTTON_GAP.y),
		)
	%Name.text = _bag_name()
	_portrait.texture = _bag_icon()
	refresh()
	show()


func close() -> void:
	if visible:
		hide()
		closed.emit(bag)


# ContainerFrame_Update: each button shows the item in its slot; button 1 is the last slot.
func refresh() -> void:
	for j: int in _size:
		var item: int = Inventory.container_item(bag, _slot(j))
		var item_entry: int = Inventory.entry(item)
		var icon: Texture2D = Inventory.icon(item_entry) if item_entry else null
		_buttons[j].set_item(icon, Inventory.stack_count(item))
	if _money.visible:
		_money.set_money(Inventory.money())


func slot_button(slot: int) -> ItemButton:
	return _buttons[_size - 1 - slot]


func _slot(button_index: int) -> int:
	return _size - 1 - button_index


# Bags stack a top piece, up to two middle pieces of six rows, and a bottom from one sheet.
func _layout_bag_background(rows: int) -> float:
	if _size % COLUMNS == 2:
		_set_texture(_top, BAG_BACKGROUND, 0.189453125, 0.330078125)
		_top.size.y = 72.0
	elif rows == 1:
		_set_texture(_top, BAG_BACKGROUND, 0.00390625, 0.16796875)
		_top.size.y = 86.0
	else:
		_set_texture(_top, BAG_BACKGROUND, 0.00390625, 0.18359375)
		_top.size.y = 94.0
	_set_texture(_bottom, BAG_BACKGROUND, 0.330078125, 0.349609375)
	_bottom.size.y = BOTTOM_HEIGHT
	_bottom.show()
	var y: float = _top.size.y
	var remaining: int = rows - 1
	for middle: TextureRect in [_middle, _middle_extra]:
		if remaining <= 0:
			break
		var height: float = ROW_HEIGHT * mini(remaining, ROWS_IN_BG_TEXTURE)
		if remaining <= ROWS_IN_BG_TEXTURE:
			height -= FIRST_ROW_PIXELS
		var bottom: float = FIRST_ROW_TEXCOORD + height / BG_TEXTURE_HEIGHT
		_set_texture(middle, BAG_BACKGROUND, FIRST_ROW_TEXCOORD, bottom)
		middle.position.y = y
		middle.size.y = height
		middle.show()
		y += height
		remaining -= ROWS_IN_BG_TEXTURE
	_top.position.y = 0.0
	_bottom.position.y = y
	return y + BOTTOM_HEIGHT


func _set_texture(rect: TextureRect, file: String, top: float, bottom: float) -> void:
	var sheet: WowTexture = WowTexture.new()
	sheet.file = file
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = sheet
	var height: float = sheet.get_height()
	atlas.region = Rect2(0.0, top * height, sheet.get_width(), (bottom - top) * height)
	rect.texture = atlas


func _bag_name() -> String:
	if bag == Inventory.BACKPACK:
		return WowStrings.get_text("BACKPACK_TOOLTIP")
	if bag == Inventory.KEYRING:
		return WowStrings.get_text("KEYRING")
	var info: Dictionary = WowClient.session.get_item_info(_bag_entry())
	return info.get("name", "")


func _bag_icon() -> Texture2D:
	if bag in [Inventory.BACKPACK, Inventory.KEYRING]:
		var icon: WowTexture = WowTexture.new()
		icon.file = BACKPACK_ICON if bag == Inventory.BACKPACK else KEYRING_ICON
		return icon
	return Inventory.icon(_bag_entry())


func _bag_entry() -> int:
	return Inventory.entry(Inventory.container_of(bag))


func _on_button_used(button_index: int) -> void:
	item_used.emit(bag, _slot(button_index))


func _on_button_entered(button_index: int) -> void:
	item_hovered.emit(bag, _slot(button_index), _buttons[button_index])
