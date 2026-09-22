class_name GuildBankFrame
extends Control

signal close_requested
signal money_requested(deposit: bool)
signal item_hovered(button: ItemButton, item_entry: int)
signal item_left(button: ItemButton)

const COLUMNS: int = 7
const ROWS: int = 14
const COPPER_PER_GOLD: int = 10000
# GetGuildBankTabCost: each next tab's price in gold.
const TAB_PRICES: Array[int] = [100, 250, 500, 1000, 2500, 5000]
const ICON_PATH: String = "Interface\\Icons\\%s"
# A tab bought but not yet given an icon.
const UNNAMED_TAB_ICON: String = "INV_Misc_QuestionMark"
const NEW_TAB_ICON: String = "Interface\\GuildBankFrame\\UI-GuildBankFrame-NewTab"
const MONEY_UNITS: Dictionary[String, int] = {"g": COPPER_PER_GOLD, "s": 100, "c": 1}

var tab: int = 0

@onready var _bank: GuildBank = WowClient.guild_bank


func _ready() -> void:
	for column: int in COLUMNS:
		for row: int in ROWS:
			var slot: int = column * ROWS + row
			var button: ItemButton = _slot_button(slot)
			button.right_clicked.connect(_on_slot_right_clicked.bind(slot))
			button.mouse_entered.connect(_on_slot_hovered.bind(slot))
			button.mouse_exited.connect(func() -> void: item_left.emit(button))
	for i: int in GuildBank.MAX_TABS:
		var tab_button: BaseButton = get_node("%%GuildBankTab%dButton" % (i + 1))
		tab_button.pressed.connect(_select_tab.bind(i))
	$Button.pressed.connect(close_requested.emit)
	%GuildBankFrameDepositButton.pressed.connect(money_requested.emit.bind(true))
	%GuildBankFrameWithdrawButton.pressed.connect(money_requested.emit.bind(false))
	%GuildBankFramePurchaseButton.pressed.connect(func() -> void: _bank.buy_tab(tab))
	# The logs and tab info tabs are not offered, so the first tab stays selected.
	for hidden: String in [
		"GuildBankInfo", "GuildBankMessageFrame", "GuildBankFrameTab2", "GuildBankFrameTab3",
		"GuildBankFrameTab4",
	]:
		(get_node("%" + hidden) as CanvasItem).hide()
	PanelManager.select_tab(%GuildBankFrameTab1, true)
	_bank.opened.connect(func() -> void: _select_tab(0))
	_bank.changed.connect(refresh)
	visibility_changed.connect(refresh)


# The first empty slot of the open tab for a bag item right-clicked while the vault is open.
func deposit(bag: int, slot: int) -> bool:
	if not is_visible_in_tree() or tab >= _bank.tabs.size():
		return false
	var slots: Array = _bank.items.get(tab, [])
	var free: int = slots.find({})
	if free < 0:
		return false
	_bank.deposit_item(tab, free, Inventory.wire_address(bag, slot))
	return true


# GuildBankFrame_Update and GuildBankFrame_UpdateTabs for the Guild Bank tab.
func refresh() -> void:
	if not is_visible_in_tree():
		return
	var bought: int = _bank.tabs.size()
	(%GuildBankMoneyFrame as MoneyFrame).set_money(_bank.money)
	# The tab after the last bought one is the purchase tab, shown instead of the slots.
	var buying: bool = tab == bought and bought < GuildBank.MAX_TABS
	%GuildBankErrorMessage.visible = bought == 0 and not buying
	for column: int in COLUMNS:
		(get_node("%%GuildBankColumn%d" % (column + 1)) as CanvasItem).visible = tab < bought
	%GuildBankTabTitle.text = _bank.tabs[tab]["name"] if tab < bought else ""
	for i: int in GuildBank.MAX_TABS:
		var tab_frame: CanvasItem = get_node("%%GuildBankTab%d" % (i + 1))
		tab_frame.visible = i <= bought
		if i <= bought:
			var icon: TextureRect = get_node("%%GuildBankTab%dButtonIconTexture" % (i + 1))
			var tab_icon: String = _bank.tabs[i]["icon"] if i < bought else ""
			if i < bought and tab_icon.is_empty():
				tab_icon = UNNAMED_TAB_ICON
			icon.texture = WowAssets.spells.icon_texture(
				ICON_PATH % tab_icon if i < bought else NEW_TAB_ICON
			)
			(get_node("%%GuildBankTab%dButton" % (i + 1)) as WowButton).checked = i == tab
	%GuildBankFrameBuyInfo.visible = buying
	if buying:
		var cost: MoneyFrame = %GuildBankFrameTabCostMoneyFrame
		cost.set_money(TAB_PRICES[bought] * COPPER_PER_GOLD)
	var slots: Array = _bank.items.get(tab, [])
	for slot: int in GuildBank.SLOTS:
		var stack: Dictionary = slots[slot] if slot < slots.size() else {}
		var button: ItemButton = _slot_button(slot)
		if stack.is_empty():
			button.set_item(null)
		else:
			button.set_item(Inventory.icon(stack["item"]), stack["count"])


# The bank's money typed as gold, or as amounts ending in g, s and c.
static func parse_money(text: String) -> int:
	var copper: int = 0
	for word: String in text.to_lower().split(" ", false):
		var unit: String = word.right(1)
		if MONEY_UNITS.has(unit):
			copper += roundi(word.left(-1).to_float() * MONEY_UNITS[unit])
		else:
			copper += roundi(word.to_float() * COPPER_PER_GOLD)
	return copper


func _select_tab(index: int) -> void:
	tab = index
	if index < _bank.tabs.size():
		_bank.query_tab(index)
	refresh()


func _slot_button(slot: int) -> ItemButton:
	var column: int = floori(slot / float(ROWS))
	return get_node("%%GuildBankColumn%dButton%d" % [column + 1, slot % ROWS + 1])


func _stack(slot: int) -> Dictionary:
	var slots: Array = _bank.items.get(tab, [])
	return slots[slot] if slot < slots.size() else {}


func _on_slot_right_clicked(slot: int) -> void:
	if not _stack(slot).is_empty():
		_bank.withdraw_item(tab, slot)


func _on_slot_hovered(slot: int) -> void:
	var stack: Dictionary = _stack(slot)
	if not stack.is_empty():
		item_hovered.emit(_slot_button(slot), stack["item"])
