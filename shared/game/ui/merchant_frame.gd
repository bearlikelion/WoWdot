class_name MerchantFrame
extends Control

signal close_requested
signal open_requested
signal backpack_requested(is_open: bool)
signal error_raised(text: String)

enum Tab { MERCHANT = 1, BUYBACK }

const MERCHANT_ITEMS_PER_PAGE: int = 10
const BUYBACK_ITEMS_PER_PAGE: int = 12
const UNLIMITED: int = -1
const NPC_FLAG_REPAIR: int = 0x4000
# Buyback slots come after the equipment, bag, backpack and bank slots.
const BUYBACK_SLOT_START: int = 69
# SMSG_BUY_FAILED and SMSG_SELL_ITEM reasons, as the error line words them.
const BUY_ERRORS: Dictionary[int, String] = {
	0: "ERR_ITEM_NOT_FOUND", 2: "ERR_NOT_ENOUGH_MONEY", 4: "ERR_VENDOR_HATES_YOU",
	5: "ERR_VENDOR_TOO_FAR", 7: "ERR_VENDOR_SOLD_OUT", 8: "ERR_ITEM_MAX_COUNT",
}
const SELL_ERRORS: Dictionary[int, String] = {
	1: "ERR_ITEM_NOT_FOUND", 2: "ERR_VENDOR_NOT_INTERESTED", 3: "ERR_VENDOR_TOO_FAR",
	4: "ERR_ITEM_NOT_FOUND",
}
const BUYBACK_ICON: String = "Interface\\MerchantFrame\\UI-BuyBack-Icon.blp"
const PORTRAIT: PackedScene = preload("res://game/ui/unit_portrait.tscn")
const PORTRAIT_MASK: Shader = preload("res://game/ui/portrait.gdshader")
# MerchantItem3 onwards sit this far under the pair above, closer on the merchant tab.
const MERCHANT_ROW_GAP: float = 8.0
const BUYBACK_ROW_GAP: float = 15.0
const COIN_SOUND: String = "LOOTWINDOWCOINSOUND"

var _guid: int = 0
var _items: Array[Dictionary] = []
var _page: int = 0
var _tab: Tab = Tab.MERCHANT
var _portrait: UnitPortrait
var _portrait_texture: Texture2D
var _buyback_icon: WowTexture = WowTexture.new()


func _ready() -> void:
	_buyback_icon.file = BUYBACK_ICON
	for i: int in BUYBACK_ITEMS_PER_PAGE:
		var button: ItemButton = _button(i)
		button.pressed.connect(_on_item_clicked.bind(i, false))
		button.right_clicked.connect(_on_item_clicked.bind(i, true))
		button.mouse_entered.connect(_on_item_entered.bind(i))
		button.mouse_exited.connect(_hide_tooltip.bind(button))
	var buyback_button: ItemButton = %MerchantBuyBackItemItemButton
	buyback_button.pressed.connect(_buy_back.bind(-1))
	buyback_button.right_clicked.connect(_buy_back.bind(-1))
	buyback_button.mouse_entered.connect(_on_buyback_entered.bind(buyback_button, -1))
	buyback_button.mouse_exited.connect(_hide_tooltip.bind(buyback_button))
	for tab: Tab in [Tab.MERCHANT, Tab.BUYBACK]:
		(get_node("%%MerchantFrameTab%d" % tab) as BaseButton).pressed.connect(_show_tab.bind(tab))
	%MerchantPrevPageButton.pressed.connect(_turn_page.bind(-1))
	%MerchantNextPageButton.pressed.connect(_turn_page.bind(1))
	%MerchantRepairAllButton.pressed.connect(_repair_all)
	%MerchantRepairItemButton.hide()
	%MerchantFrameCloseButton.pressed.connect(close_requested.emit)
	_portrait = PORTRAIT.instantiate()
	add_child(_portrait)
	var mask: ShaderMaterial = ShaderMaterial.new()
	mask.shader = PORTRAIT_MASK
	%MerchantFramePortrait.material = mask
	_portrait_texture = _portrait.get_texture()
	var session: WowSession = WowClient.session
	session.merchant_inventory_received.connect(_on_inventory_received)
	session.merchant_stock_changed.connect(_on_stock_changed)
	session.merchant_buy_failed.connect(_on_failed.bind(BUY_ERRORS))
	session.merchant_sell_failed.connect(_on_failed.bind(SELL_ERRORS))
	session.item_info_received.connect(func(_entry: int) -> void: refresh())
	session.object_updated.connect(_on_object_updated)
	visibility_changed.connect(_on_visibility_changed)


func vendor() -> int:
	return _guid if is_visible_in_tree() else 0


# Right-clicking a bag item while the merchant is open sells it.
func sell(item: int) -> void:
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(17)
	payload.encode_u64(0, _guid)
	payload.encode_u64(8, item)
	WowAssets.audio.play_sound(COIN_SOUND)
	WowClient.session.send_packet("CMSG_SELL_ITEM", payload)


# MerchantFrame_Update.
func refresh() -> void:
	if not is_visible_in_tree():
		return
	for tab: Tab in [Tab.MERCHANT, Tab.BUYBACK]:
		PanelManager.select_tab(get_node("%%MerchantFrameTab%d" % tab), tab == _tab)
	var merchant: bool = _tab == Tab.MERCHANT
	for node_name: String in [
		"BuybackFrameTopLeft", "BuybackFrameTopRight", "BuybackFrameBotLeft", "BuybackFrameBotRight",
		"MerchantItem11", "MerchantItem12",
	]:
		(get_node("%" + node_name) as CanvasItem).visible = not merchant
	for node_name: String in [
		"MerchantBuyBackItem", "MerchantFrameBottomLeftBorder", "MerchantFrameBottomRightBorder",
	]:
		(get_node("%" + node_name) as CanvasItem).visible = merchant
	var gap: float = MERCHANT_ROW_GAP if merchant else BUYBACK_ROW_GAP
	for i: int in range(2, BUYBACK_ITEMS_PER_PAGE, 2):
		var above: Control = _slot(i - 2)
		var row: Control = _slot(i)
		row.position.y = above.position.y + above.size.y + gap
		_slot(i + 1).position.y = row.position.y
	if merchant:
		_update_merchant()
	else:
		_update_buyback()


func _update_merchant() -> void:
	var session: WowSession = WowClient.session
	%MerchantNameText.text = session.get_object_name(_guid)
	%MerchantFramePortrait.texture = _portrait_texture
	var pages: int = maxi(ceili(_items.size() / float(MERCHANT_ITEMS_PER_PAGE)), 1)
	_page = clampi(_page, 0, pages - 1)
	for i: int in MERCHANT_ITEMS_PER_PAGE:
		var index: int = _page * MERCHANT_ITEMS_PER_PAGE + i
		if index < _items.size():
			var item: Dictionary = _items[index]
			_show_item(i, item["entry"], item["price"], item["count"], item["stock"])
		else:
			_show_item(i, 0, 0, 0, UNLIMITED)
	var paged: bool = _items.size() > MERCHANT_ITEMS_PER_PAGE
	for node_name: String in ["MerchantPageText", "MerchantPrevPageButton", "MerchantNextPageButton"]:
		(get_node("%" + node_name) as CanvasItem).visible = paged
	%MerchantPageText.text = WowStrings.get_text("PAGE_NUMBER") % (_page + 1)
	(%MerchantPrevPageButton as BaseButton).disabled = _page == 0
	(%MerchantNextPageButton as BaseButton).disabled = _page == pages - 1
	var repairs: bool = session.get_field(_guid, "UNIT_NPC_FLAGS") & NPC_FLAG_REPAIR != 0
	%MerchantRepairText.visible = repairs
	%MerchantRepairAllButton.visible = repairs
	var buyback: Array[int] = _buyback_items()
	var last: int = buyback.size() - 1
	var buyback_entry: int = Inventory.entry(buyback[last]) if last >= 0 else 0
	var name_label: Label = %MerchantBuyBackItemName
	name_label.text = session.get_item_info(buyback_entry).get("name", "") if buyback_entry else ""
	var button: ItemButton = %MerchantBuyBackItemItemButton
	button.set_item(Inventory.icon(buyback_entry) if buyback_entry else null, \
	Inventory.stack_count(buyback[last]) if last >= 0 else 0)
	var money: MoneyFrame = %MerchantBuyBackItemMoneyFrame
	money.visible = buyback_entry != 0
	if money.visible:
		money.set_money(_buyback_price(last))


# MerchantFrame_UpdateBuybackInfo: what was sold this session, most recent last.
func _update_buyback() -> void:
	%MerchantNameText.text = WowStrings.get_text("MERCHANT_BUYBACK")
	%MerchantFramePortrait.texture = _buyback_icon
	var buyback: Array[int] = _buyback_items()
	for i: int in BUYBACK_ITEMS_PER_PAGE:
		var item: int = buyback[i] if i < buyback.size() else 0
		_show_item(i, Inventory.entry(item), _buyback_price(i), Inventory.stack_count(item), UNLIMITED)
	for node_name: String in [
		"MerchantPageText", "MerchantPrevPageButton", "MerchantNextPageButton", "MerchantRepairText",
		"MerchantRepairAllButton",
	]:
		(get_node("%" + node_name) as CanvasItem).hide()


func _show_item(index: int, entry: int, price: int, count: int, stock: int) -> void:
	var prefix: String = "%%MerchantItem%d" % (index + 1)
	var button: ItemButton = _button(index)
	var info: Dictionary = WowClient.session.get_item_info(entry) if entry else {}
	(get_node(prefix + "Name") as Label).text = info.get("name", "")
	button.visible = entry != 0
	button.set_item(Inventory.icon(entry) if entry else null, count)
	var stock_label: Label = button.get_node("%Stock")
	stock_label.text = str(stock)
	stock_label.visible = entry != 0 and stock != UNLIMITED
	var money: MoneyFrame = get_node(prefix + "MoneyFrame")
	money.visible = entry != 0
	if entry:
		money.set_money(price)
	var slot: CanvasItem = get_node(prefix + "SlotTexture")
	slot.self_modulate = Color.WHITE if entry else Color(0.4, 0.4, 0.4)


# The sold items the buyback fields still hold, in slot order.
func _buyback_items() -> Array[int]:
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	var first: int = session.field_index("PLAYER_FIELD_VENDORBUYBACK_SLOT_1")
	var items: Array[int] = []
	for i: int in BUYBACK_ITEMS_PER_PAGE:
		var item: int = session.get_field(guid, first + i * 2) \
		| (session.get_field(guid, first + i * 2 + 1) << 32)
		if item:
			items.append(item)
	return items


func _buyback_price(index: int) -> int:
	var session: WowSession = WowClient.session
	var first: int = session.field_index("PLAYER_FIELD_BUYBACK_PRICE_1")
	return session.get_field(session.get_player_guid(), first + index) if index >= 0 else 0


func _button(index: int) -> ItemButton:
	return get_node("%%MerchantItem%dItemButton" % (index + 1))


func _slot(index: int) -> Control:
	return get_node("%%MerchantItem%d" % (index + 1))


func _show_tab(tab: Tab) -> void:
	_tab = tab
	refresh()


func _turn_page(step: int) -> void:
	_page += step
	refresh()


# MerchantItemButton_OnClick: a right click buys one lot; buyback buys back either way.
func _on_item_clicked(index: int, right_click: bool) -> void:
	if _tab == Tab.BUYBACK:
		_buy_back(index)
		return
	var item_index: int = _page * MERCHANT_ITEMS_PER_PAGE + index
	if item_index >= _items.size():
		return
	# MerchantItemButton_OnClick: a Ctrl click tries the item on in the dressing room.
	if not right_click and Input.is_key_pressed(KEY_CTRL) and ItemButton.dress_up.is_valid():
		ItemButton.dress_up.call(_items[item_index]["entry"])
		return
	if not right_click:
		return
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(14)
	payload.encode_u64(0, _guid)
	payload.encode_u32(8, _items[item_index]["entry"])
	payload.encode_u8(12, 1)
	WowAssets.audio.play_sound(COIN_SOUND)
	WowClient.session.send_packet("CMSG_BUY_ITEM", payload)


func _buy_back(index: int) -> void:
	var slot: int = index if index >= 0 else _buyback_items().size() - 1
	if slot < 0:
		return
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(12)
	payload.encode_u64(0, _guid)
	payload.encode_u32(8, BUYBACK_SLOT_START + slot)
	WowClient.session.send_packet("CMSG_BUYBACK_ITEM", payload)


func _repair_all() -> void:
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(16)
	payload.encode_u64(0, _guid)
	WowClient.session.send_packet("CMSG_REPAIR_ITEM", payload)


func _on_item_entered(index: int) -> void:
	if GameTooltip.current == null:
		return
	var button: ItemButton = _button(index)
	if _tab == Tab.BUYBACK:
		_on_buyback_entered(button, index)
		return
	var item_index: int = _page * MERCHANT_ITEMS_PER_PAGE + index
	if item_index < _items.size():
		GameTooltip.current.set_item(button, _items[item_index]["entry"])


func _on_buyback_entered(button: ItemButton, index: int) -> void:
	var buyback: Array[int] = _buyback_items()
	var slot: int = index if index >= 0 else buyback.size() - 1
	if GameTooltip.current and slot >= 0 and slot < buyback.size():
		GameTooltip.current.set_item(button, Inventory.entry(buyback[slot]), buyback[slot])


func _hide_tooltip(tooltip_owner: Control) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(tooltip_owner)


func _on_inventory_received(inventory: Dictionary) -> void:
	_guid = inventory["guid"]
	_items.assign(inventory["items"])
	_page = 0
	_tab = Tab.MERCHANT
	_portrait.show_unit(_guid)
	open_requested.emit()
	refresh()


func _on_stock_changed(slot: int, stock: int) -> void:
	for item: Dictionary in _items:
		if item["slot"] == slot:
			item["stock"] = stock
	refresh()


func _on_failed(reason: int, errors: Dictionary[int, String]) -> void:
	if errors.has(reason):
		error_raised.emit(WowStrings.get_text(errors[reason]))


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid() and is_visible_in_tree():
		refresh()


# MerchantFrame_OnShow and OnHide open and close the backpack with the merchant.
func _on_visibility_changed() -> void:
	backpack_requested.emit(visible)
	refresh()
