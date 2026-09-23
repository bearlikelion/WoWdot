class_name TemporaryEnchantFrame
extends Control

signal enchants_changed(count: int)

# BuffFrame_Enchant_OnUpdate fills TempEnchant1 with the off hand first.
const HANDS: Array[Inventory.Slot] = [Inventory.Slot.OFF_HAND, Inventory.Slot.MAIN_HAND]
const BUTTONS: int = 2
const TEMP_ENCHANTMENT_SLOT: int = 1
# ITEM_FIELD_ENCHANTMENT holds an id, duration and charges per enchantment slot.
const ENCHANTMENT_FIELDS: int = 3

# Item guid to the tick its temporary enchant runs out, from SMSG_ITEM_ENCHANT_TIME_UPDATE.
var _ends: Dictionary[int, int] = {}
var _shown: Array[int] = []
var _buttons: Array[WowButton] = []
var _icons: Array[TextureRect] = []
var _durations: Array[Label] = []


func _ready() -> void:
	for i: int in range(1, BUTTONS + 1):
		var button: WowButton = get_node("%%TempEnchant%d" % i)
		button.mouse_entered.connect(_on_button_entered.bind(i - 1))
		button.mouse_exited.connect(_on_button_exited.bind(i - 1))
		_buttons.append(button)
		_icons.append(get_node("%%TempEnchant%dIcon" % i))
		(get_node("%%TempEnchant%dCount" % i) as Label).hide()
		var duration: Label = get_node("%%TempEnchant%dDuration" % i)
		BuffFrame.place_duration(button, duration)
		_durations.append(duration)
	var session: WowSession = WowClient.session
	session.object_updated.connect(_on_object_updated)
	session.packet_received.connect(_on_packet_received)
	refresh()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	var pulse: float = absf(
		fmod(now / 1000.0, BuffFrame.FLASH_SECONDS * 2.0) - BuffFrame.FLASH_SECONDS
	) / BuffFrame.FLASH_SECONDS
	for i: int in _shown.size():
		var end: int = _ends.get(_shown[i], 0)
		var left: int = end - now
		_durations[i].visible = end > 0 and left > 0 \
		and WowAssets.interface.is_on(&"show_buff_durations")
		if _durations[i].visible:
			_durations[i].text = BuffFrame.duration_text(left)
		_buttons[i].modulate.a = lerpf(BuffFrame.MIN_ALPHA, 1.0, pulse) \
				if end > 0 and left < BuffFrame.WARNING_MSEC else 1.0


# GetWeaponEnchantInfo: the worn weapons carrying a poison, oil or stone.
func refresh() -> void:
	var session: WowSession = WowClient.session
	var enchant_field: int = session.field_index("ITEM_FIELD_ENCHANTMENT") \
			+ TEMP_ENCHANTMENT_SLOT * ENCHANTMENT_FIELDS
	var count: int = _shown.size()
	_shown.clear()
	for hand: Inventory.Slot in HANDS:
		var item: int = Inventory.equipped(hand)
		if item and session.get_field(item, enchant_field) != 0:
			_shown.append(item)
	for i: int in BUTTONS:
		_buttons[i].visible = i < _shown.size()
		_durations[i].visible = false
		if i < _shown.size():
			_icons[i].texture = Inventory.icon(Inventory.entry(_shown[i]))
	set_process(not _shown.is_empty())
	if count != _shown.size():
		enchants_changed.emit(_shown.size())


func _on_object_updated(guid: int) -> void:
	var session: WowSession = WowClient.session
	if guid == session.get_player_guid() or _shown.has(guid) \
	or HANDS.any(func(hand: Inventory.Slot) -> bool: return Inventory.equipped(hand) == guid):
		refresh()


# The item guid, the enchantment slot, its seconds left, then the player's guid.
func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_ITEM_ENCHANT_TIME_UPDATE" or payload.size() < 16:
		return
	if payload.decode_u32(8) == TEMP_ENCHANTMENT_SLOT:
		_ends[payload.decode_u64(0)] = Time.get_ticks_msec() + payload.decode_u32(12) * 1000


# BuffFrame_EnchantButton_OnEnter: the weapon's own tooltip.
func _on_button_entered(index: int) -> void:
	if index < _shown.size() and GameTooltip.current:
		var item: int = _shown[index]
		GameTooltip.current.set_item(
			_buttons[index], Inventory.entry(item), item, GameTooltip.TooltipAnchor.BOTTOM_LEFT
		)


func _on_button_exited(index: int) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(_buttons[index])
