class_name Inventory
extends RefCounted

# Inventory slot ids, in PLAYER_FIELD_INV_SLOT_HEAD order.
enum Slot {
	HEAD, NECK, SHOULDER, SHIRT, CHEST, WAIST, LEGS, FEET, WRIST, HANDS, FINGER_1, FINGER_2,
	TRINKET_1, TRINKET_2, BACK, MAIN_HAND, OFF_HAND, RANGED, TABARD, BAG_1, BAG_2, BAG_3, BAG_4,
}

# Container ids as the stock UI numbers them: the backpack is 0 and the bag slots 1 to 4.
const BACKPACK: int = 0
const BAG_COUNT: int = 4
# Bank bags carry on the numbering the stock UI gives the worn ones.
const BANK_BAG_FIRST: int = 5
const BACKPACK_SLOTS: int = 16
# The wire addresses the backpack as bag 255, its slots as inventory slots 23 to 38.
const WIRE_BACKPACK: int = 255
const WIRE_PACK_SLOT_START: int = 23
const WIRE_BANK_SLOT_START: int = 39
const WIRE_BANK_SLOTS: int = 24
const WIRE_BANK_BAG_START: int = 63
const WIRE_BANK_BAGS: int = 6
const ICON_PATH: String = "Interface\\Icons\\%s.blp"
const ITEM_FLAG_SOULBOUND: int = 0x1

static var _displays: WowDBC
static var _icons: Dictionary[int, Texture2D] = {}


static func equipped(slot: Slot) -> int:
	var session: WowSession = WowClient.session
	var first: int = session.field_index("PLAYER_FIELD_INV_SLOT_HEAD")
	return _guid(session.get_player_guid(), first + slot * 2)


static func bank_bag(index: int) -> int:
	return item_at(Vector2i(WIRE_BACKPACK, WIRE_BANK_BAG_START + index))


# The container worn or banked in a bag slot, or 0 when the slot is empty.
static func container_of(bag: int) -> int:
	if bag >= BANK_BAG_FIRST:
		return bank_bag(bag - BANK_BAG_FIRST)
	return equipped((Slot.BAG_1 + bag - 1) as Slot)


static func container_size(bag: int) -> int:
	if bag == BACKPACK:
		return BACKPACK_SLOTS
	var container: int = container_of(bag)
	return WowClient.session.get_field(container, "CONTAINER_FIELD_NUM_SLOTS") if container else 0


# The item in a container slot, counted from 0, or 0 when it is empty.
static func container_item(bag: int, slot: int) -> int:
	var session: WowSession = WowClient.session
	if bag == BACKPACK:
		return _guid(
			session.get_player_guid(), session.field_index("PLAYER_FIELD_PACK_SLOT_1") + slot * 2
		)
	var container: int = container_of(bag)
	if container == 0:
		return 0
	return _guid(container, session.field_index("CONTAINER_FIELD_SLOT_1") + slot * 2)


# The bag and slot bytes CMSG_USE_ITEM and CMSG_AUTOEQUIP_ITEM take for a container slot.
static func wire_address(bag: int, slot: int) -> Vector2i:
	if bag == BACKPACK:
		return Vector2i(WIRE_BACKPACK, WIRE_PACK_SLOT_START + slot)
	if bag >= BANK_BAG_FIRST:
		return Vector2i(WIRE_BANK_BAG_START + bag - BANK_BAG_FIRST, slot)
	return Vector2i(Slot.BAG_1 + bag - 1, slot)


# Equipment, bags, the backpack and the bank are one guid array from the head slot on.
static func item_at(address: Vector2i) -> int:
	var session: WowSession = WowClient.session
	var first: int = session.field_index("PLAYER_FIELD_INV_SLOT_HEAD")
	if address.x == WIRE_BACKPACK:
		return _guid(session.get_player_guid(), first + address.y * 2)
	var container: int = _guid(session.get_player_guid(), first + address.x * 2)
	if container == 0:
		return 0
	return _guid(container, session.field_index("CONTAINER_FIELD_SLOT_1") + address.y * 2)


# Moving within the player's own container takes CMSG_SWAP_INV_ITEM, anything else CMSG_SWAP_ITEM.
static func move(from: Vector2i, to: Vector2i) -> void:
	if from == to:
		return
	var session: WowSession = WowClient.session
	if from.x == WIRE_BACKPACK and to.x == WIRE_BACKPACK:
		session.send_packet("CMSG_SWAP_INV_ITEM", PackedByteArray([from.y, to.y]))
	else:
		session.send_packet("CMSG_SWAP_ITEM", PackedByteArray([to.x, to.y, from.x, from.y]))


static func split(from: Vector2i, to: Vector2i, count: int) -> void:
	WowClient.session.send_packet(
		"CMSG_SPLIT_ITEM", PackedByteArray([from.x, from.y, to.x, to.y, count])
	)


# The server reads three more bytes after the count and ignores them.
static func destroy(at: Vector2i, count: int) -> void:
	WowClient.session.send_packet(
		"CMSG_DESTROYITEM", PackedByteArray([at.x, at.y, count, 0, 0, 0])
	)


# The first bag and slot holding an item, or -1, -1 when none does.
static func find_item(item_entry: int) -> Vector2i:
	for bag: int in BAG_COUNT + 1:
		for slot: int in container_size(bag):
			if entry(container_item(bag, slot)) == item_entry:
				return Vector2i(bag, slot)
	return -Vector2i.ONE


# How many of an item the backpack and bags hold, as GetItemCount counts them.
static func item_count(item_entry: int) -> int:
	var total: int = 0
	for bag: int in BAG_COUNT + 1:
		for slot: int in container_size(bag):
			var item: int = container_item(bag, slot)
			if item and entry(item) == item_entry:
				total += stack_count(item)
	return total


static func entry(item: int) -> int:
	return WowClient.session.get_field(item, "OBJECT_FIELD_ENTRY") if item else 0


static func stack_count(item: int) -> int:
	return WowClient.session.get_field(item, "ITEM_FIELD_STACK_COUNT") if item else 0


static func is_soulbound(item: int) -> bool:
	return WowClient.session.get_field(item, "ITEM_FIELD_FLAGS") & ITEM_FLAG_SOULBOUND != 0


static func money() -> int:
	var session: WowSession = WowClient.session
	return session.get_field(session.get_player_guid(), "PLAYER_FIELD_COINAGE")


# The item's icon, or null while its SMSG_ITEM_QUERY_SINGLE_RESPONSE is still out.
static func icon(item_entry: int) -> Texture2D:
	var info: Dictionary = WowClient.session.get_item_info(item_entry)
	if info.is_empty():
		return null
	return display_icon(info["display_id"])


static func display_icon(display_id: int) -> Texture2D:
	if not _icons.has(display_id):
		if _displays == null:
			_displays = WowDBC.open(WowAssets.archive, "ItemDisplayInfo")
		var row: int = _displays.find(display_id)
		var file: String = _displays.get_string(row, "InventoryIcon") if row >= 0 else ""
		var texture: WowTexture = null
		if not file.is_empty():
			texture = WowTexture.new()
			texture.file = ICON_PATH % file
		_icons[display_id] = texture
	return _icons[display_id]


static func _guid(object: int, field: int) -> int:
	var session: WowSession = WowClient.session
	return session.get_field(object, field) | (session.get_field(object, field + 1) << 32)
