class_name LootFrame
extends Control

signal close_requested
signal open_requested
signal error_raised(text: String)
signal message_added(text: String)
signal money_looted(text: String)
signal master_loot_requested(slot: int, candidates: PackedInt64Array)

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
const SLOT_TYPE_MASTER: int = 2
const COIN_SOUND: String = "LOOTWINDOWCOINSOUND"
const ITEM_SOUND: String = "INTERFACESOUND_CURSORDROPOBJECT"
const GROUP_SOUND_COLUMN: int = 11
const PICKUP_KIT_COLUMN: int = 1

static var _displays: WowDBC
static var _group_sounds: WowDBC

var _guid: int = 0
var _money: int = 0
# Each is a wire slot, or COIN_SLOT for the money.
var _slots: Array[int] = []
var _candidates: PackedInt64Array = []
var _items: Dictionary[int, Dictionary] = {}
var _page: int = 0
var _released: bool = true
# Item pushes whose name the server had not told us yet, by entry.
var _unnamed_pushes: Dictionary[int, PackedByteArray] = {}


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
	session.item_info_received.connect(_on_item_named)
	visibility_changed.connect(_on_visibility_changed)


# LootUnit: the server answers with the loot, or with why not.
static func loot(guid: int) -> void:
	NpcDialog.send("CMSG_LOOT", guid)


# CMSG_LOOT_MASTER_GIVE: the corpse, the slot and who gets it.
func give(slot: int, receiver: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(17)
	payload.encode_u64(0, _guid)
	payload.encode_u8(8, slot)
	payload.encode_u64(9, receiver)
	WowClient.session.send_packet("CMSG_LOOT_MASTER_GIVE", payload)


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
		"SMSG_LOOT_MASTER_LIST":
			_candidates.clear()
			for i: int in payload.decode_u8(0):
				_candidates.append(payload.decode_u64(1 + i * 8))
		"SMSG_LOOT_ALL_PASSED":
			var entry: int = payload.decode_u32(12)
			var item_name: String = WowClient.session.get_item_info(entry).get("name", "")
			message_added.emit(WowStrings.format(WowStrings.get_text("LOOT_ROLL_ALL_PASSED"), [item_name]))
		"SMSG_ITEM_PUSH_RESULT":
			_on_item_pushed(payload)
		"SMSG_LOOT_MONEY_NOTIFY":
			var text: String = WowStrings.get_text("YOU_LOOT_MONEY")
			money_looted.emit(text % money_text(payload.decode_u32(0)))


# The chat line for SMSG_ITEM_PUSH_RESULT, or "" when the server asks for none.
static func push_text(payload: PackedByteArray, item_name: String, me: int) -> String:
	var reader: PacketReader = PacketReader.new(payload)
	var receiver: int = reader.u64()
	var from_npc: bool = reader.u32() != 0
	var created: bool = reader.u32() != 0
	if reader.u32() == 0:
		return ""
	reader.skip(17)
	var count: int = reader.u32()
	var args: Array = [item_name, count]
	var key: String = "LOOT_ITEM"
	if receiver == me:
		key += "_CREATED_SELF" if created else "_PUSHED_SELF" if from_npc else "_SELF"
	else:
		args.push_front(WowClient.session.get_object_name(receiver))
	if count > 1:
		key += "_MULTIPLE"
	return WowStrings.format(WowStrings.get_text(key), args)


func _on_item_pushed(payload: PackedByteArray) -> void:
	var entry: int = payload.decode_u32(25) if payload.size() >= 41 else 0
	var item_name: String = WowClient.session.get_item_info(entry).get("name", "")
	if item_name.is_empty():
		_unnamed_pushes[entry] = payload
		return
	var text: String = push_text(payload, item_name, WowClient.session.get_player_guid())
	if not text.is_empty():
		message_added.emit(text)


func _on_item_named(entry: int) -> void:
	_refresh()
	if _unnamed_pushes.has(entry):
		var payload: PackedByteArray = _unnamed_pushes[entry]
		_unnamed_pushes.erase(entry)
		_on_item_pushed(payload)


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
			"master": payload.decode_u8(offset + 21) == SLOT_TYPE_MASTER,
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
			text.text = money_text(_money)
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
	if _items[slot]["master"] and not _candidates.is_empty():
		master_loot_requested.emit(slot, _candidates)
		return
	_play_pickup(_items[slot].get("entry", 0))
	WowClient.session.send_packet("CMSG_AUTOSTORE_LOOT_ITEM", PackedByteArray([slot]))


# The item's ItemDisplayInfo names an ItemGroupSounds row, whose first kit is the pickup.
func _play_pickup(entry: int) -> void:
	var display_id: int = WowClient.session.get_item_info(entry).get("display_id", 0)
	if _displays == null:
		_displays = WowDBC.open(WowAssets.archive, "ItemDisplayInfo")
		_group_sounds = WowDBC.open(WowAssets.archive, "ItemGroupSounds")
	var display_row: int = _displays.find(display_id)
	var group_row: int = -1
	if display_row >= 0:
		group_row = _group_sounds.find(_displays.get_uint(display_row, GROUP_SOUND_COLUMN))
	if group_row >= 0 and _group_sounds.get_uint(group_row, PICKUP_KIT_COLUMN) != 0:
		WowAssets.audio.play_entry(_group_sounds.get_uint(group_row, PICKUP_KIT_COLUMN))
	else:
		WowAssets.audio.play_sound(ITEM_SOUND)


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


static func money_text(copper: int) -> String:
	var parts: PackedStringArray = []
	var amounts: Array[int] = [copper % 100, floori(copper / 100.0) % 100, floori(copper / 10000.0)]
	for tier: int in [2, 1, 0]:
		if amounts[tier] > 0:
			parts.append("%d %s" % [amounts[tier], WowStrings.get_text(COIN_NAMES[tier])])
	return ", ".join(parts)
