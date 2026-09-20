class_name LootFrame
extends Control

signal close_requested
signal open_requested
signal error_raised(text: String)
signal message_added(text: String)

const BUTTON_COUNT: int = 4
# SMSG_LOOT_RESPONSE with loot type 0 carries one of these instead of loot.
const ERRORS: Dictionary[int, String] = {
	0: "ERR_LOOT_DIDNT_KILL", 4: "ERR_LOOT_TOO_FAR", 5: "ERR_LOOT_BAD_FACING",
	6: "ERR_LOOT_LOCKED", 8: "ERR_LOOT_NOTSTANDING", 9: "ERR_LOOT_STUNNED",
	10: "ERR_LOOT_PLAYER_NOT_FOUND", 12: "ERR_LOOT_MASTER_INV_FULL",
	13: "ERR_LOOT_MASTER_UNIQUE_ITEM", 14: "ERR_LOOT_MASTER_OTHER",
}
const COIN_ICONS: Array[String] = [
	"Interface\\Icons\\INV_Misc_Coin_05", "Interface\\Icons\\INV_Misc_Coin_03",
	"Interface\\Icons\\INV_Misc_Coin_01",
]
const COIN_NAMES: PackedStringArray = ["COPPER", "SILVER", "GOLD"]
const COIN_SLOT: int = -1
const COIN_SOUND: String = "LOOTWINDOWCOINSOUND"
const ITEM_SOUND: String = "INTERFACESOUND_CURSORDROPOBJECT"

var _guid: int = 0
var _money: int = 0
# Each is a wire slot, or COIN_SLOT for the money.
var _slots: Array[int] = []
var _items: Dictionary[int, Dictionary] = {}
var _page: int = 0
var _released: bool = true


func _ready() -> void:
	for i: int in BUTTON_COUNT:
		var button: ItemButton = _button(i)
		button.pressed.connect(_on_button_pressed.bind(i))
		button.right_clicked.connect(_on_button_pressed.bind(i))
		button.mouse_entered.connect(_on_button_entered.bind(i))
		button.mouse_exited.connect(_hide_tooltip.bind(button))
	%LootCloseButton.pressed.connect(close_requested.emit)
	%LootFrameUpButton.pressed.connect(_turn_page.bind(-1))
	%LootFrameDownButton.pressed.connect(_turn_page.bind(1))
	var session: WowSession = WowClient.session
	session.packet_received.connect(_on_packet_received)
	session.item_info_received.connect(func(_entry: int) -> void: _refresh())
	visibility_changed.connect(_on_visibility_changed)


# LootUnit: the server answers with the loot, or with why not.
static func loot(guid: int) -> void:
	NpcDialog.send("CMSG_LOOT", guid)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	match opcode:
		"SMSG_LOOT_RESPONSE":
			_on_loot_received(payload)
		"SMSG_LOOT_REMOVED":
			_slots.erase(payload.decode_u8(0))
			_after_removal()
		"SMSG_LOOT_CLEAR_MONEY":
			_slots.erase(COIN_SLOT)
			_after_removal()
		"SMSG_LOOT_RELEASE_RESPONSE":
			_released = true
			close_requested.emit()
		"SMSG_LOOT_MONEY_NOTIFY":
			var text: String = WowStrings.get_text("YOU_LOOT_MONEY")
			message_added.emit(text % _money_text(payload.decode_u32(0)))


func _on_loot_received(payload: PackedByteArray) -> void:
	_guid = payload.decode_u64(0)
	if payload.decode_u8(8) == 0:
		var code: int = payload.decode_u8(9) if payload.size() > 9 else 0
		if ERRORS.has(code):
			error_raised.emit(WowStrings.get_text(ERRORS[code]))
		return
	_money = payload.decode_u32(9)
	_slots.clear()
	_items.clear()
	if _money > 0:
		_slots.append(COIN_SLOT)
	var offset: int = 14
	for i: int in payload.decode_u8(13):
		var slot: int = payload.decode_u8(offset)
		_items[slot] = {
			"entry": payload.decode_u32(offset + 1),
			"count": payload.decode_u32(offset + 5),
			"display_id": payload.decode_u32(offset + 9),
		}
		_slots.append(slot)
		# Asking for the item's info fetches it, and its arrival redraws the rows.
		WowClient.session.get_item_info(_items[slot]["entry"])
		offset += 22
	_page = 0
	_released = false
	if _slots.is_empty():
		_release()
		return
	_refresh()
	open_requested.emit()


# LootFrame_Update: four rows, or three with the page arrows once there are more.
func _refresh() -> void:
	if not is_visible_in_tree() and _released:
		return
	var per_page: int = _per_page()
	for i: int in BUTTON_COUNT:
		var button: ItemButton = _button(i)
		var index: int = _page * per_page + i
		button.visible = i < per_page and index < _slots.size()
		if not button.visible:
			continue
		var text: Label = button.get_node("%Text")
		# The white font of the same size, so the quality colour is not mixed with gold.
		text.theme_type_variation = &"GameFontHighlight"
		if _slots[index] == COIN_SLOT:
			button.set_item(_coin_icon())
			text.text = _money_text(_money)
			text.self_modulate = Color.WHITE
			continue
		var item: Dictionary = _items[_slots[index]]
		var info: Dictionary = WowClient.session.get_item_info(item["entry"])
		button.set_item(Inventory.display_icon(item["display_id"]), item["count"])
		text.text = info.get("name", "")
		var quality: int = clampi(info.get("quality", 1), 0, GameTooltip.QUALITY_COLORS.size() - 1)
		text.self_modulate = GameTooltip.QUALITY_COLORS[quality]
	var paged: bool = _slots.size() > BUTTON_COUNT
	%LootFrameUpButton.visible = paged and _page > 0
	%LootFramePrev.visible = paged and _page > 0
	%LootFrameDownButton.visible = paged and (_page + 1) * per_page < _slots.size()
	%LootFrameNext.visible = %LootFrameDownButton.visible


func _after_removal() -> void:
	if _slots.is_empty():
		close_requested.emit()
		return
	_page = mini(_page, floori((_slots.size() - 1) / float(_per_page())))
	_refresh()


func _per_page() -> int:
	return BUTTON_COUNT if _slots.size() <= BUTTON_COUNT else BUTTON_COUNT - 1


func _turn_page(by: int) -> void:
	_page = clampi(_page + by, 0, floori((_slots.size() - 1) / float(_per_page())))
	_refresh()


func _on_button_pressed(index: int) -> void:
	var slot: int = _slots[_page * _per_page() + index]
	if slot == COIN_SLOT:
		WowAssets.audio.play_sound(COIN_SOUND)
		WowClient.session.send_packet("CMSG_LOOT_MONEY", PackedByteArray())
		return
	# ponytail: one sound for every item, where the stock client picks it by the item's material.
	WowAssets.audio.play_sound(ITEM_SOUND)
	WowClient.session.send_packet("CMSG_AUTOSTORE_LOOT_ITEM", PackedByteArray([slot]))


func _on_button_entered(index: int) -> void:
	var slot: int = _slots[_page * _per_page() + index]
	if slot != COIN_SLOT and GameTooltip.current:
		GameTooltip.current.set_item(_button(index), _items[slot]["entry"])


func _hide_tooltip(button: ItemButton) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(button)


# CloseLoot: the corpse stays locked to this player until it is released.
func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_release()


func _release() -> void:
	if _released:
		return
	_released = true
	NpcDialog.send("CMSG_LOOT_RELEASE", _guid)


func _button(index: int) -> ItemButton:
	return get_node("%%LootButton%d" % (index + 1))


func _coin_icon() -> WowTexture:
	var tier: int = 2 if _money >= 10000 else 1 if _money >= 100 else 0
	return WowAssets.spells.icon_texture(COIN_ICONS[tier])


func _money_text(copper: int) -> String:
	var parts: PackedStringArray = []
	var amounts: Array[int] = [copper % 100, floori(copper / 100.0) % 100, floori(copper / 10000.0)]
	for tier: int in [2, 1, 0]:
		if amounts[tier] > 0:
			parts.append("%d %s" % [amounts[tier], WowStrings.get_text(COIN_NAMES[tier])])
	return ", ".join(parts)
