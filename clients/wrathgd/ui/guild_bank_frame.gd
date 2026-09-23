class_name GuildBankFrame
extends Control

signal close_requested
signal money_requested(deposit: bool)
signal item_hovered(button: ItemButton, item_entry: int)
signal item_left(button: ItemButton)

# GuildBankFrame.mode, one per bottom tab.
enum Mode { BANK, LOG, MONEY_LOG, INFO }

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
const LOG_TIME_COLOR: String = "|cff009999   "
const MONEY_FORMATS: Dictionary[GuildBank.LogType, String] = {
	GuildBank.LogType.DEPOSIT_MONEY: "GUILDBANK_DEPOSIT_MONEY_FORMAT",
	GuildBank.LogType.WITHDRAW_MONEY: "GUILDBANK_WITHDRAW_MONEY_FORMAT",
	GuildBank.LogType.REPAIR_MONEY: "GUILDBANK_REPAIR_MONEY_FORMAT",
	GuildBank.LogType.WITHDRAW_FOR_TAB: "GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT",
	GuildBank.LogType.BUY_SLOT: "GUILDBANK_BUYTAB_MONEY_FORMAT",
}
# Each bottom tab overlaps the one before it, as their LEFT to RIGHT anchors offset by -16.
const TAB_OVERLAP: float = -16.0
const UNLIMITED_GAP: float = 5.0
const WITHDRAW_MONEY_GAP: float = 13.0
const HOUR: int = 3600
const DAY: int = 86400
const MONTH: int = DAY * 30
const YEAR: int = DAY * 365

var tab: int = 0
var mode: Mode = Mode.BANK

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
	var bottom_tabs: Array[Control] = []
	for i: int in Mode.size():
		var bottom_tab: BaseButton = get_node("%%GuildBankFrameTab%d" % (i + 1))
		bottom_tab.pressed.connect(_set_mode.bind(i as Mode))
		bottom_tabs.append(bottom_tab)
	PanelManager.chain_tabs(bottom_tabs, TAB_OVERLAP)
	var limit: Label = %GuildBankMoneyLimitLabel
	var limit_right: float = limit.position.x + limit.get_minimum_size().x
	%GuildBankMoneyUnlimitedLabel.position.x = limit_right + UNLIMITED_GAP
	%GuildBankWithdrawMoneyFrame.position.x = limit_right + WITHDRAW_MONEY_GAP
	(%GuildBankMessageFrame as WowScrollingMessageFrame).display_duration = INF
	%GuildBankInfoSaveButton.pressed.connect(
		func() -> void: _bank.set_text(tab, (%GuildBankTabInfoEditBox as TextEdit).text)
	)
	_bank.opened.connect(func() -> void: _set_mode(Mode.BANK))
	_bank.changed.connect(refresh)
	_bank.log_received.connect(func(_log_tab: int) -> void: _write_log())
	_bank.text_received.connect(_on_text_received)
	WowClient.session.name_received.connect(func(_guid: int, _name: String) -> void: _write_log())
	WowClient.session.item_info_received.connect(func(_entry: int) -> void: _write_log())
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
	# GuildBankFrame_UpdateWithdrawMoney.
	%GuildBankMoneyUnlimitedLabel.visible = _bank.money_remaining < 0
	%GuildBankWithdrawMoneyFrame.visible = _bank.money_remaining >= 0
	(%GuildBankWithdrawMoneyFrame as MoneyFrame).set_money(mini(_bank.money_remaining, _bank.money))
	# The tab after the last bought one is the purchase tab, shown instead of the slots.
	var buying: bool = mode == Mode.BANK and tab == bought and bought < GuildBank.MAX_TABS
	%GuildBankErrorMessage.visible = bought == 0 and not buying
	for column: int in COLUMNS:
		(get_node("%%GuildBankColumn%d" % (column + 1)) as CanvasItem).visible = \
				mode == Mode.BANK and tab < bought
	%GuildBankFrameLog.visible = mode == Mode.LOG or mode == Mode.MONEY_LOG
	%GuildBankInfo.visible = mode == Mode.INFO
	%GuildBankTabTitle.text = _title(_bank.tabs[tab]["name"] if tab < bought else "")
	for i: int in GuildBank.MAX_TABS:
		var tab_frame: CanvasItem = get_node("%%GuildBankTab%d" % (i + 1))
		tab_frame.visible = i <= bought
		(get_node("%%GuildBankTab%dButton" % (i + 1)) as BaseButton).disabled = \
				mode == Mode.MONEY_LOG or (mode != Mode.BANK and i >= bought)
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


# RecentTimeDate over the seconds since the entry.
static func time_ago(seconds: int) -> String:
	if seconds >= YEAR:
		return _text("LASTONLINE_YEARS", [floori(seconds / float(YEAR))])
	if seconds >= MONTH:
		return _text("LASTONLINE_MONTHS", [floori(seconds / float(MONTH))])
	if seconds >= DAY:
		return _text("LASTONLINE_DAYS", [floori(seconds / float(DAY))])
	if seconds >= HOUR:
		return _text("LASTONLINE_HOURS", [floori(seconds / float(HOUR))])
	return WowStrings.get_text("LASTONLINE_MINS")


func _select_tab(index: int) -> void:
	tab = index
	_query()
	refresh()


# GuildBankFrameTab_OnClick.
func _set_mode(to: Mode) -> void:
	mode = to
	for i: int in Mode.size():
		PanelManager.select_tab(get_node("%%GuildBankFrameTab%d" % (i + 1)), i == mode)
	if mode != Mode.BANK and mode != Mode.MONEY_LOG:
		tab = mini(tab, maxi(_bank.tabs.size() - 1, 0))
	(%GuildBankMessageFrame as WowScrollingMessageFrame).clear()
	_query()
	refresh()


func _query() -> void:
	var bought: bool = tab < _bank.tabs.size()
	match mode:
		Mode.BANK:
			if bought:
				_bank.query_tab(tab)
		Mode.LOG:
			if bought:
				_bank.query_log(tab)
		Mode.MONEY_LOG:
			_bank.query_log(GuildBank.MONEY_LOG)
		Mode.INFO:
			if bought:
				_bank.query_text(tab)


func _title(tab_name: String) -> String:
	match mode:
		Mode.LOG:
			return _text("GUILDBANK_LOG_TITLE_FORMAT", [tab_name])
		Mode.MONEY_LOG:
			return WowStrings.get_text("GUILD_BANK_MONEY_LOG")
		Mode.INFO:
			return _text("GUILDBANK_INFO_TITLE_FORMAT", [tab_name])
	return tab_name


# GuildBankFrame_UpdateLog and _UpdateMoneyLog, newest at the bottom.
func _write_log() -> void:
	if mode != Mode.LOG and mode != Mode.MONEY_LOG:
		return
	var frame: WowScrollingMessageFrame = %GuildBankMessageFrame
	frame.clear()
	var log_tab: int = GuildBank.MONEY_LOG if mode == Mode.MONEY_LOG else tab
	for entry: Dictionary in _bank.logs.get(log_tab, []):
		var line: String = _log_line(entry)
		if not line.is_empty():
			var ago: String = _text("GUILD_BANK_LOG_TIME", [time_ago(entry["seconds"])])
			frame.add_message(line + LOG_TIME_COLOR + ago)


func _log_line(entry: Dictionary) -> String:
	var who: String = WowClient.session.get_object_name(entry["player"])
	who = "|cffffd100%s|r" % (who if who else WowStrings.get_text("UNKNOWN"))
	var type: GuildBank.LogType = entry["type"] as GuildBank.LogType
	if MONEY_FORMATS.has(type):
		var money: String = LootFrame.money_text(entry["money"])
		return _text(MONEY_FORMATS[type], [who, money])
	var item: String = _item_link(entry["item"])
	var count: int = entry["count"]
	var quantity: String = ""
	if count > 1:
		quantity = WowStrings.get_text("GUILDBANK_LOG_QUANTITY") % count
	match type:
		GuildBank.LogType.DEPOSIT_ITEM:
			return _text("GUILDBANK_DEPOSIT_FORMAT", [who, item]) + quantity
		GuildBank.LogType.WITHDRAW_ITEM:
			return _text("GUILDBANK_WITHDRAW_FORMAT", [who, item]) + quantity
		GuildBank.LogType.MOVE_ITEM, GuildBank.LogType.MOVE_ITEM2:
			return _text("GUILDBANK_MOVE_FORMAT", [
				who, item, count, _tab_name(tab), _tab_name(entry["tab"]),
			])
	return ""


func _item_link(entry: int) -> String:
	var info: Dictionary = WowClient.session.get_item_info(entry)
	var quality: int = clampi(info.get("quality", 1), 0, GameTooltip.QUALITY_COLORS.size() - 1)
	return "|cff%s[%s]|r" % [
		GameTooltip.QUALITY_COLORS[quality].to_html(false), info.get("name", ""),
	]


func _tab_name(index: int) -> String:
	return _bank.tabs[index]["name"] if index < _bank.tabs.size() else ""


static func _text(key: String, args: Array) -> String:
	return WowStrings.format(WowStrings.get_text(key), args)


func _on_text_received(text_tab: int) -> void:
	if text_tab == tab:
		(%GuildBankTabInfoEditBox as TextEdit).text = _bank.texts[text_tab]


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
