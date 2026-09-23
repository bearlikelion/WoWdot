class_name TotemFrame
extends Control

signal totem_hovered(button: Control, spell_id: int)
signal totem_left(button: Control)

const BUTTONS: int = 4
# TOTEM_PRIORITIES by the wire's slot, which counts fire, earth, water, air from 0.
const PRIORITIES: Array[int] = [1, 0, 2, 3]

# Wire slot to its totem as {guid, spell, start, duration}, both times in msec.
var _totems: Dictionary[int, Dictionary] = {}


func _ready() -> void:
	for i: int in BUTTONS:
		var button: BaseButton = _button(i)
		button.gui_input.connect(_on_button_input.bind(i))
		button.mouse_entered.connect(_on_button_hovered.bind(i))
		button.mouse_exited.connect(func() -> void: totem_left.emit(button))
	WowClient.session.packet_received.connect(_on_packet_received)
	WowClient.session.objects_destroyed.connect(_on_objects_destroyed)
	refresh()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	var expired: Array[int] = []
	for slot: int in _totems:
		var totem: Dictionary = _totems[slot]
		if now >= totem["start"] + totem["duration"]:
			expired.append(slot)
	for slot: int in expired:
		_totems.erase(slot)
	if not expired.is_empty():
		refresh()
	for i: int in BUTTONS:
		var slot: int = _slot_at(i)
		if slot >= 0:
			var totem: Dictionary = _totems[slot]
			var left: float = (totem["start"] + totem["duration"] - now) / 1000.0
			(get_node("%%TotemFrameTotem%dDuration" % (i + 1)) as Label).text = _time_text(left)


# TotemFrame_Update: the live totems fill the buttons in priority order.
func refresh() -> void:
	visible = not _totems.is_empty()
	set_process(visible)
	for i: int in BUTTONS:
		var slot: int = _slot_at(i)
		var button: CanvasItem = _button(i)
		button.visible = slot >= 0
		if slot < 0:
			continue
		var totem: Dictionary = _totems[slot]
		var prefix: String = "%%TotemFrameTotem%d" % (i + 1)
		(get_node(prefix + "IconTexture") as TextureRect).texture = \
				WowAssets.spells.icon(totem["spell"])
		var cooldown: WowCooldown = get_node(prefix + "IconCooldown")
		cooldown.start(totem["start"], totem["duration"])


# The wire slot shown on a button, or -1.
func _slot_at(index: int) -> int:
	var shown: int = 0
	for slot: int in PRIORITIES:
		if _totems.has(slot):
			if shown == index:
				return slot
			shown += 1
	return -1


func _button(index: int) -> BaseButton:
	return get_node("%%TotemFrameTotem%d" % (index + 1))


static func _time_text(seconds: float) -> String:
	return "%dm" % ceili(seconds / 60.0) if seconds >= 60.0 else "%ds" % ceili(seconds)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_TOTEM_CREATED":
		return
	var reader: PacketReader = PacketReader.new(payload)
	var slot: int = reader.u8()
	var guid: int = reader.u64()
	var duration: int = reader.u32()
	var spell: int = reader.u32()
	if guid == 0 or duration == 0:
		_totems.erase(slot)
	else:
		_totems[slot] = {
			"guid": guid, "spell": spell, "start": Time.get_ticks_msec(), "duration": duration,
		}
	refresh()


func _on_objects_destroyed(guids: PackedInt64Array) -> void:
	for slot: int in _totems.keys():
		if _totems[slot]["guid"] in guids:
			_totems.erase(slot)
	refresh()


# Right-clicking a totem button dismisses that totem, as DestroyTotem does.
func _on_button_input(event: InputEvent, index: int) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_RIGHT or click.pressed:
		return
	var slot: int = _slot_at(index)
	if slot >= 0:
		WowClient.session.send_packet("CMSG_TOTEM_DESTROYED", PackedByteArray([slot]))


func _on_button_hovered(index: int) -> void:
	var slot: int = _slot_at(index)
	if slot >= 0:
		totem_hovered.emit(_button(index), _totems[slot]["spell"])
