class_name TokenFrame
extends Control

signal close_requested

# GetCurrencyListInfo's extraCurrencyType: the two point pools that are player fields, not items.
enum Extra { NONE, ARENA, HONOR }

const BUTTONS: int = 16
const ARENA_POINTS_ITEM: int = 43307
const HONOR_POINTS_ITEM: int = 43308
const CURRENCY_SLOT_FIRST: int = 118
const CURRENCY_SLOTS: int = 32
const ARENA_ICON: String = "Interface\\PVPFrame\\PVP-ArenaPoints-Icon.blp"
const FACTION_ICON: String = "Interface\\TargetingFrame\\UI-PVP-%s.blp"
const HONOR_UV: Rect2 = Rect2(0.03125, 0.03125, 0.5625, 0.5625)
const PLUS_MINUS: String = "Interface\\Buttons\\UI-PlusMinus-Buttons.blp"
const EXPANDED_UV: Rect2 = Rect2(0.5625, 0.0, 0.4375, 0.4375)
const COLLAPSED_UV: Rect2 = Rect2(0.0, 0.0, 0.4375, 0.4375)
const ITEM_HIGHLIGHT: String = "Interface\\QuestFrame\\UI-QuestTitleHighlight.blp"
const CATEGORY_INSET: Vector2 = Vector2(3.0, 2.0)

# GetCurrencyListInfo rows: category headers, each followed by its currencies unless collapsed.
var _entries: Array[Dictionary] = []
var _collapsed: Dictionary[int, bool] = {}
var _offset: int = 0
var _types: WowDBC
var _categories: WowDBC
var _textures: Dictionary[String, Texture2D] = {}

@onready var _scroll: WowScrollFrame = %TokenFrameContainer


func _ready() -> void:
	_types = WowDBC.open(WowAssets.archive, "CurrencyTypes")
	_categories = WowDBC.open(WowAssets.archive, "CurrencyCategory")
	_textures[ARENA_ICON] = _cropped(ARENA_ICON, Rect2(0.0, 0.0, 1.0, 1.0))
	_textures["Expanded"] = _cropped(PLUS_MINUS, EXPANDED_UV)
	_textures["Collapsed"] = _cropped(PLUS_MINUS, COLLAPSED_UV)
	_textures[ITEM_HIGHLIGHT] = _cropped(ITEM_HIGHLIGHT, Rect2(0.0, 0.0, 1.0, 1.0))
	_textures["Category"] = _highlight(0).texture
	for faction: String in ["Alliance", "Horde"]:
		_textures[faction] = _cropped(FACTION_ICON % faction, HONOR_UV)
	for i: int in BUTTONS:
		var button: WowButton = _button(i)
		button.pressed.connect(_on_button_pressed.bind(i))
		(get_node(_prefix(i) + "Check") as CanvasItem).hide()
		# TokenFrame_OnLoad hides the stripe on every odd row.
		(get_node(_prefix(i) + "Stripe") as CanvasItem).visible = i % 2 == 1
		var link: Control = button.get_node("Button")
		link.mouse_entered.connect(_on_link_hovered.bind(i))
		link.mouse_exited.connect(_on_link_left.bind(link))
	# ponytail: no inactive or backpack options; they are client-side settings no server stores.
	%TokenFramePopup.hide()
	%TokenFrameCancelButton.pressed.connect(close_requested.emit)
	($Button as BaseButton).pressed.connect(close_requested.emit)
	_scroll.faux = true
	_scroll.scrolled.connect(_on_scrolled)
	WowClient.session.item_info_received.connect(func(_entry: int) -> void: refresh())
	WowClient.session.object_updated.connect(_on_object_updated)
	visibility_changed.connect(refresh)


func has_currencies() -> bool:
	return _known() != 0


func refresh() -> void:
	if not is_visible_in_tree():
		return
	(%TokenFrameMoneyFrame as MoneyFrame).set_money(Inventory.money())
	_list()
	_scroll.set_range(maxi(_entries.size() - BUTTONS, 0))
	_show()


func _known() -> int:
	var session: WowSession = WowClient.session
	var first: int = session.field_index("PLAYER_FIELD_KNOWN_CURRENCIES")
	var guid: int = session.get_player_guid()
	return session.get_field(guid, first) | (session.get_field(guid, first + 1) << 32)


# Categories and the currencies within them run in name order, as the stock list sorts them.
func _list() -> void:
	var known: int = _known()
	var by_category: Dictionary[int, Array] = {}
	for row: int in _types.row_count():
		var bit: int = _types.get_uint(row, "BitIndex")
		if bit == 0 or known & (1 << (bit - 1)) == 0:
			continue
		var item_entry: int = _types.get_uint(row, "ItemID")
		var info: Dictionary = WowClient.session.get_item_info(item_entry)
		var category: int = _types.get_uint(row, "CategoryID")
		if not by_category.has(category):
			by_category[category] = []
		by_category[category].append({
			"name": info.get("name", ""),
			"item": item_entry,
			"count": _count(item_entry),
			"extra": _extra(item_entry),
			"display_id": info.get("display_id", 0),
		})
	var headers: Array[Dictionary] = []
	for category: int in by_category:
		var row: int = _categories.find(category)
		var header_name: String = _categories.get_string(row, "Name") if row >= 0 else ""
		headers.append({"name": header_name, "category": category})
	headers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
	_entries.clear()
	for header: Dictionary in headers:
		_entries.append(header)
		if _collapsed.get(header["category"], false):
			continue
		var currencies: Array = by_category[header["category"]]
		currencies.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"]
		)
		_entries.append_array(currencies)


func _count(item_entry: int) -> int:
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	match _extra(item_entry):
		Extra.ARENA:
			return session.get_field(guid, "PLAYER_FIELD_ARENA_CURRENCY")
		Extra.HONOR:
			return session.get_field(guid, "PLAYER_FIELD_HONOR_CURRENCY")
	var total: int = 0
	for item: int in _token_items():
		if item and Inventory.entry(item) == item_entry:
			total += Inventory.stack_count(item)
	return total


static func _extra(item_entry: int) -> Extra:
	if item_entry == ARENA_POINTS_ITEM:
		return Extra.ARENA
	return Extra.HONOR if item_entry == HONOR_POINTS_ITEM else Extra.NONE


# TokenFrame_Update: a header shows its name over the category bar, a currency its count and icon.
func _show() -> void:
	for i: int in BUTTONS:
		var button: WowButton = _button(i)
		var index: int = _offset + i
		button.visible = index < _entries.size()
		if not button.visible:
			continue
		var entry: Dictionary = _entries[index]
		var header: bool = entry.has("category")
		var prefix: String = _prefix(i)
		for part: String in ["CategoryLeft", "CategoryRight", "ExpandIcon"]:
			(get_node(prefix + part) as CanvasItem).visible = header
		(get_node(prefix + "Text") as Label).text = entry["name"] if header else ""
		(get_node(prefix + "Name") as Label).text = "" if header else entry["name"]
		var count: Label = get_node(prefix + "Count")
		var icon: TextureRect = get_node(prefix + "Icon")
		(button.get_node("Button") as CanvasItem).visible = not header
		var highlight: TextureRect = _highlight(i)
		if header:
			count.text = ""
			icon.texture = null
			var collapsed: bool = _collapsed.get(entry["category"], false)
			(get_node(prefix + "ExpandIcon") as TextureRect).texture = \
					_textures["Collapsed" if collapsed else "Expanded"]
			highlight.texture = _textures["Category"]
			highlight.position = CATEGORY_INSET
			highlight.size = button.size - CATEGORY_INSET * 2.0
			continue
		count.text = str(entry["count"])
		icon.texture = _icon(entry)
		highlight.texture = _textures[ITEM_HIGHLIGHT]
		highlight.position = Vector2.ZERO
		highlight.size = button.size
		var font: StringName = &"GameFontDisable" if entry["count"] == 0 else &"GameFontHighlight"
		count.theme_type_variation = font
		(get_node(prefix + "Name") as Label).theme_type_variation = font


func _icon(entry: Dictionary) -> Texture2D:
	match entry["extra"]:
		Extra.ARENA:
			return _textures[ARENA_ICON]
		Extra.HONOR:
			var race: int = WowClient.session.get_field(
				WowClient.session.get_player_guid(), "UNIT_FIELD_BYTES_0"
			) & 0xFF
			var alliance: bool = \
					CharacterOptions.faction(race) == CharacterOptions.Faction.ALLIANCE
			return _textures["Alliance" if alliance else "Horde"]
	return Inventory.display_icon(entry["display_id"]) if entry["display_id"] else null


func _cropped(file: String, uv: Rect2) -> AtlasTexture:
	var texture: WowTexture = WowTexture.new()
	texture.file = file
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = texture
	var texture_size: Vector2 = texture.get_size()
	atlas.region = Rect2(uv.position * texture_size, uv.size * texture_size)
	return atlas


func _prefix(index: int) -> String:
	return "%%TokenFrameContainerButton%d" % (index + 1)


func _button(index: int) -> WowButton:
	return get_node(_prefix(index))


func _highlight(index: int) -> TextureRect:
	return _button(index).get_node("HighlightTexture")


func _on_button_pressed(index: int) -> void:
	var entry: Dictionary = _entries[_offset + index]
	if entry.has("category"):
		_collapsed[entry["category"]] = not _collapsed.get(entry["category"], false)
		refresh()


func _on_link_hovered(index: int) -> void:
	var entry: Dictionary = _entries[_offset + index]
	var link: Control = _button(index).get_node("Button")
	if GameTooltip.current == null:
		return
	match entry["extra"]:
		Extra.ARENA:
			GameTooltip.current.set_text(
				link, WowStrings.get_text("ARENA_POINTS"),
				WowStrings.get_text("TOOLTIP_ARENA_POINTS"),
			)
		Extra.HONOR:
			GameTooltip.current.set_text(
				link, WowStrings.get_text("HONOR_POINTS"),
				WowStrings.get_text("TOOLTIP_HONOR_POINTS"),
			)
		_:
			GameTooltip.current.set_item(link, entry["item"])


func _on_link_left(link: Control) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(link)


# A token's stack is its own object, so its count changes without the player updating.
func _on_object_updated(guid: int) -> void:
	if not is_visible_in_tree():
		return
	if guid == WowClient.session.get_player_guid() or guid in _token_items():
		refresh()


func _token_items() -> Array[int]:
	var items: Array[int] = []
	for slot: int in CURRENCY_SLOTS:
		var address: Vector2i = Vector2i(Inventory.WIRE_BACKPACK, CURRENCY_SLOT_FIRST + slot)
		items.append(Inventory.item_at(address))
	return items


func _on_scrolled(value: float) -> void:
	_offset = roundi(value)
	_show()
