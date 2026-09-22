@tool
class_name PetStableFrame
extends Control

signal open_requested
signal close_requested
signal error_raised(text: String)

# SMSG_STABLE_RESULT, as NPCHandler's StableResultCode numbers them.
enum Result { NO_MONEY = 0x01, FAILED = 0x06, STABLED = 0x08, UNSTABLED = 0x09,
	SLOT_BOUGHT = 0x0A }

# NUM_PET_STABLE_SLOTS, and the wire counts the pet at the player's side as slot 1.
const STABLE_SLOTS: int = 2
const CURRENT_SLOT: int = 1
# CreatureFamily.dbc: the family's name, then the icon the stable slot wears.
const FAMILY_NAME_COLUMN: int = 8
const FAMILY_ICON_COLUMN: int = 17

var _guid: int = 0
var _pets: Array[Dictionary] = []
var _bought_slots: int = 0
var _selected: int = CURRENT_SLOT

static var _families: WowDBC
static var _prices: WowDBC


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	(%PetStableCurrentPet as BaseButton).pressed.connect(_on_slot_pressed.bind(CURRENT_SLOT))
	for i: int in STABLE_SLOTS:
		var slot: BaseButton = get_node("%%PetStableStabledPet%d" % (i + 1))
		slot.pressed.connect(_on_slot_pressed.bind(i + 2))
	%PetStablePurchaseButton.pressed.connect(_buy_slot)
	%PetStableFrameCloseButton.pressed.connect(close_requested.emit)
	WowClient.session.packet_received.connect(_on_packet_received)
	hide()


# MSG_LIST_STABLED_PETS: right-clicking a stable master asks for the pets they keep.
func list_pets(guid: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, guid)
	WowClient.session.send_packet("MSG_LIST_STABLED_PETS", payload)


func refresh() -> void:
	_show_slot(%PetStableCurrentPet, _pet_in(CURRENT_SLOT))
	for i: int in STABLE_SLOTS:
		var slot: Control = get_node("%%PetStableStabledPet%d" % (i + 1))
		slot.visible = i < _bought_slots
		if slot.visible:
			_show_slot(slot, _pet_in(i + 2))
	var chosen: Dictionary = _pet_in(_selected)
	(%PetStableLevelText as Label).text = "" if chosen.is_empty() else "%s %s %s" % [
		chosen["name"], WowStrings.get_text("UNIT_LEVEL_TEMPLATE") % chosen["level"],
		_family_of(chosen["entry"]),
	]
	(%PetStableLoyaltyText as Label).text = "" if chosen.is_empty() else str(chosen["loyalty"])
	var cost: int = _slot_cost()
	(%PetStableCostMoneyFrame as MoneyFrame).set_money(cost)
	(%PetStableMoneyFrame as MoneyFrame).set_money(Inventory.money())
	for part: CanvasItem in [%PetStablePurchaseButton, %PetStableCostLabel, %PetStableCostMoneyFrame]:
		part.visible = cost > 0
	(%PetStablePurchaseButton as BaseButton).disabled = cost > Inventory.money()
	%PetStableSlotText.hide()


# The stock UI drags a pet between slots; here a click on the other slot moves it.
func _on_slot_pressed(slot: int) -> void:
	var pet: Dictionary = _pet_in(slot)
	if slot == CURRENT_SLOT or _selected == slot:
		_selected = slot
		refresh()
		return
	if pet.is_empty():
		_send_to_master("CMSG_STABLE_PET")
	elif _pet_in(CURRENT_SLOT).is_empty():
		_send_pet_number("CMSG_UNSTABLE_PET", pet["number"])
	else:
		_send_pet_number("CMSG_STABLE_SWAP_PET", pet["number"])
	_selected = slot


func _buy_slot() -> void:
	_send_to_master("CMSG_BUY_STABLE_SLOT")


func _pet_in(slot: int) -> Dictionary:
	for pet: Dictionary in _pets:
		if pet["slot"] == slot:
			return pet
	return {}


func _show_slot(slot: Control, pet: Dictionary) -> void:
	var icon: TextureRect = slot.get_node("%s%s" % [slot.name, "IconTexture"])
	icon.visible = not pet.is_empty()
	if not pet.is_empty():
		var texture: WowTexture = WowTexture.new()
		texture.file = "%s.blp" % _family_string(pet["entry"], FAMILY_ICON_COLUMN)
		icon.texture = texture
	(slot as WowButton).checked = pet.get("slot", 0) == _selected


func _family_of(entry: int) -> String:
	return _family_string(entry, FAMILY_NAME_COLUMN)


func _family_string(entry: int, column: int) -> String:
	var info: Dictionary = WowClient.session.get_creature_template(entry)
	if _families == null:
		_families = WowDBC.open(WowAssets.archive, "CreatureFamily")
	var row: int = _families.find(info.get("family", 0))
	return _families.get_string(row, column) if row >= 0 else ""


# StableSlotPrices.dbc holds what the next slot costs, and nothing once both are bought.
func _slot_cost() -> int:
	if _bought_slots >= STABLE_SLOTS:
		return 0
	if _prices == null:
		_prices = WowDBC.open(WowAssets.archive, "StableSlotPrices")
	var row: int = _prices.find(_bought_slots + 1)
	return _prices.get_uint(row, 1) if row >= 0 else 0


func _send_to_master(opcode: String) -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, _guid)
	WowClient.session.send_packet(opcode, payload)


func _send_pet_number(opcode: String, number: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(12)
	payload.encode_u64(0, _guid)
	payload.encode_u32(8, number)
	WowClient.session.send_packet(opcode, payload)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"MSG_LIST_STABLED_PETS":
			_read_pets(reader)
		"SMSG_STABLE_RESULT":
			_on_result(reader.u8() as Result)


# The list holds the pet at the player's side first, then everything in a stable slot.
func _read_pets(reader: PacketReader) -> void:
	_guid = reader.u64()
	var count: int = reader.u8()
	_bought_slots = reader.u8()
	_pets.clear()
	for i: int in count:
		var pet: Dictionary = {"number": reader.u32(), "entry": reader.u32()}
		pet["level"] = reader.u32()
		pet["name"] = reader.cstring()
		if PacketReader.wotlk:
			# 3.3.5 dropped loyalty and flags the pet at the player's side instead of numbering slots.
			pet["loyalty"] = 0
			pet["slot"] = CURRENT_SLOT if reader.u8() == 1 else CURRENT_SLOT + _pets.size()
		else:
			pet["loyalty"] = reader.u32()
			pet["slot"] = reader.u8()
		_pets.append(pet)
		WowClient.session.get_creature_template(pet["entry"])
	refresh()
	open_requested.emit()


func _on_result(result: Result) -> void:
	if result == Result.NO_MONEY:
		error_raised.emit(WowStrings.get_text("ERR_NOT_ENOUGH_MONEY", ""))
	elif result == Result.FAILED:
		error_raised.emit(WowStrings.get_text("ERR_STABLE_ERROR", "Your pet cannot be stabled."))
	if _guid != 0:
		list_pets(_guid)
