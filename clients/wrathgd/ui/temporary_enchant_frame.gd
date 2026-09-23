class_name TemporaryEnchantFrame
extends Control

signal weapon_hovered(button: Control, item_entry: int)
signal weapon_left(button: Control)

# The item's enchantment slot a poison or oil takes, three fields per slot.
const TEMP_ENCHANTMENT_SLOT: int = 1
const ENCHANTMENT_FIELDS: int = 3
const BUTTONS: int = 2
# TemporaryEnchantFrame_OnUpdate fills the buttons off hand first.
const WEAPONS: Array[Inventory.Slot] = [Inventory.Slot.OFF_HAND, Inventory.Slot.MAIN_HAND]

# Item guid to the msec its temporary enchantment runs out, from SMSG_ITEM_ENCHANT_TIME_UPDATE.
var _expires: Dictionary[int, int] = {}
var _shown: Array[Inventory.Slot] = []


func _ready() -> void:
	for i: int in BUTTONS:
		var button: BaseButton = _button(i)
		button.gui_input.connect(_on_button_input.bind(i))
		button.mouse_entered.connect(_on_button_hovered.bind(i))
		button.mouse_exited.connect(func() -> void: weapon_left.emit(button))
	WowClient.session.packet_received.connect(_on_packet_received)
	WowClient.session.object_updated.connect(_on_object_updated)
	refresh()


func _process(_delta: float) -> void:
	for i: int in _shown.size():
		var left: int = _expires.get(Inventory.equipped(_shown[i]), 0) - Time.get_ticks_msec()
		var duration: Label = get_node("%%TempEnchant%dDuration" % (i + 1))
		duration.text = _time_text(left / 1000.0) if left > 0 else ""
		duration.visible = left > 0


func refresh() -> void:
	_shown.clear()
	for slot: Inventory.Slot in WEAPONS:
		if _enchanted(Inventory.equipped(slot)):
			_shown.append(slot)
	visible = not _shown.is_empty()
	set_process(visible)
	for i: int in BUTTONS:
		var button: CanvasItem = _button(i)
		button.visible = i < _shown.size()
		if button.visible:
			var entry: int = Inventory.entry(Inventory.equipped(_shown[i]))
			var icon: TextureRect = get_node("%%TempEnchant%dIcon" % (i + 1))
			icon.texture = Inventory.icon(entry)


static func _enchanted(item: int) -> bool:
	if item == 0:
		return false
	var session: WowSession = WowClient.session
	var field: int = session.field_index("ITEM_FIELD_ENCHANTMENT") \
			+ TEMP_ENCHANTMENT_SLOT * ENCHANTMENT_FIELDS
	return session.get_field(item, field) != 0


static func _time_text(seconds: float) -> String:
	return "%dm" % ceili(seconds / 60.0) if seconds >= 60.0 else "%ds" % ceili(seconds)


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid() \
	or guid in WEAPONS.map(func(slot: Inventory.Slot) -> int: return Inventory.equipped(slot)):
		refresh()


func _button(index: int) -> BaseButton:
	return get_node("%%TempEnchant%d" % (index + 1))


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_ITEM_ENCHANT_TIME_UPDATE":
		return
	var reader: PacketReader = PacketReader.new(payload)
	var item: int = reader.u64()
	if reader.u32() != TEMP_ENCHANTMENT_SLOT:
		return
	var seconds: int = reader.u32()
	if seconds > 0:
		_expires[item] = Time.get_ticks_msec() + seconds * 1000
	else:
		_expires.erase(item)
	refresh()


# TempEnchantButton_OnClick: a right click strips that weapon's enchantment.
func _on_button_input(event: InputEvent, index: int) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_RIGHT or click.pressed \
	or index >= _shown.size():
		return
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_u32(0, 1 if _shown[index] == Inventory.Slot.OFF_HAND else 0)
	WowClient.session.send_packet("CMSG_CANCEL_TEMP_ENCHANTMENT", payload)


func _on_button_hovered(index: int) -> void:
	if index < _shown.size():
		weapon_hovered.emit(_button(index), Inventory.entry(Inventory.equipped(_shown[index])))
