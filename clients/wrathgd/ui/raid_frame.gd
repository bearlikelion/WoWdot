class_name RaidFrame
extends Control

signal member_requested

const GROUP: PackedScene = preload("res://ui/raid_group.tscn")
const MEMBER: PackedScene = preload("res://ui/raid_group_button.tscn")
const GROUPS: int = 8
const SLOTS: int = 5
# RaidGroup1 sits here; the rest run two to a row, as the stock anchors chain them.
const FIRST_GROUP: Vector2 = Vector2(16.0, 70.0)
const COLUMN_GAP: float = 3.0
const ROW_GAP: float = 14.0
const OFFLINE_COLOR: Color = Color(0.5, 0.5, 0.5)
const RAID_INFOS: int = 10
const RESET_UNITS: PackedStringArray = ["DAYS_ABBR", "HOURS_ABBR", "MINUTES_ABBR"]

var _groups: Array[Control] = []
var _buttons: Array[Control] = []


func _ready() -> void:
	for i: int in GROUPS:
		var group: Control = GROUP.instantiate()
		add_child(group)
		group.position = FIRST_GROUP + Vector2(
			(i % 2) * (group.size.x + COLUMN_GAP), floori(i / 2.0) * (group.size.y + ROW_GAP)
		)
		(group.get_node("Label/Text") as Label).text = "%s %d" % [WowStrings.get_text("GROUP"), i + 1]
		group.set_drag_forwarding(Callable(), _can_drop_member, _drop_member.bind(i))
		for slot: Node in group.get_children():
			if slot is Control:
				(slot as Control).set_drag_forwarding(Callable(), _can_drop_member, _drop_member.bind(i))
		_groups.append(group)
	(%RaidFrameRaidDescription as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%RaidFrameConvertToRaidButton.pressed.connect(PartyFrame.convert_to_raid)
	%RaidFrameReadyCheckButton.pressed.connect(PartyFrame.start_ready_check)
	%RaidFrameAddMemberButton.pressed.connect(member_requested.emit)
	%RaidFrameRaidInfoButton.pressed.connect(_toggle_raid_info)
	%RaidInfoCloseButton.pressed.connect(%RaidInfoFrame.hide)
	%RaidInfoFrame.hide()
	visibility_changed.connect(refresh)
	WowClient.session.packet_received.connect(_on_packet_received)


# ponytail: the pulled-out on-screen raid frames are not ported.
func refresh() -> void:
	if not is_visible_in_tree():
		return
	var session: WowSession = WowClient.session
	var raid: bool = PartyFrame.is_raid
	%RaidFrameRaidDescription.visible = not raid
	var to_raid: BaseButton = %RaidFrameConvertToRaidButton
	to_raid.visible = not raid
	to_raid.disabled = not PartyFrame.in_party() or PartyFrame.leader != session.get_player_guid()
	for button: Control in _buttons:
		((button.get_parent() as Control).get_node("FontString") as Label).show()
		button.queue_free()
	_buttons.clear()
	for group: Control in _groups:
		group.visible = raid
	if not raid:
		return
	var roster: Array[Dictionary] = PartyFrame.members.duplicate()
	roster.append({
		"name": session.get_object_name(session.get_player_guid()),
		"guid": session.get_player_guid(), "online": true,
		"subgroup": PartyFrame.own_subgroup,
	})
	var filled: PackedInt32Array = []
	filled.resize(GROUPS)
	for member: Dictionary in roster:
		var group_index: int = member["subgroup"]
		if group_index >= GROUPS or filled[group_index] >= SLOTS:
			continue
		var slot: Control = _groups[group_index].get_node("Slot%d" % (filled[group_index] + 1))
		filled[group_index] += 1
		_add_member(member, slot)


# Only the leader and assistants may shuffle the groups, which the server enforces as well.
func _drag_member(_at_position: Vector2, member_name: String, button: Control) -> Variant:
	var preview: Label = Label.new()
	preview.text = member_name
	button.set_drag_preview(preview)
	return {"raid_member": member_name}


func _can_drop_member(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("raid_member")


func _drop_member(_at_position: Vector2, data: Variant, group_index: int) -> void:
	PartyFrame.move_to_subgroup(data["raid_member"], group_index)


func member_count() -> int:
	return _buttons.size()


func _add_member(member: Dictionary, slot: Control) -> void:
	var session: WowSession = WowClient.session
	var button: Control = MEMBER.instantiate()
	slot.add_child(button)
	button.position = Vector2.ZERO
	button.show()
	_buttons.append(button)
	var guid: int = member["guid"]
	var color: Color = Color.WHITE if member["online"] else OFFLINE_COLOR
	var name_label: Label = button.get_node("Name")
	name_label.text = member["name"]
	name_label.self_modulate = color
	var known: bool = session.has_object(guid)
	var level: Label = button.get_node("Level")
	level.text = str(session.get_field(guid, "UNIT_FIELD_LEVEL")) if known else ""
	var class_text: Label = button.get_node("Class/Text")
	var class_id: int = (session.get_field(guid, "UNIT_FIELD_BYTES_0") >> 8) & 0xFF if known else 0
	class_text.text = CharacterOptions.class_label(class_id) if class_id else ""
	class_text.self_modulate = color
	(button.get_node("Rank") as Label).text = ""
	button.set_drag_forwarding(_drag_member.bind(member["name"], button), Callable(), Callable())
	(slot.get_node("FontString") as Label).hide()


# Deferred so the party frame, which hears the same packet, has the new roster first.
func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode == "SMSG_GROUP_LIST":
		refresh.call_deferred()
	elif opcode == "SMSG_RAID_INSTANCE_INFO":
		_show_raid_info(payload)


func _toggle_raid_info() -> void:
	if %RaidInfoFrame.visible:
		%RaidInfoFrame.hide()
	else:
		WowClient.session.send_packet("CMSG_REQUEST_RAID_INFO", PackedByteArray())


# RaidInfoFrame_Update, with the wire's map, seconds until reset and instance id per row.
func _show_raid_info(payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	var count: int = reader.u32()
	for i: int in RAID_INFOS:
		var row: Control = get_node("%%RaidInfoInstance%d" % (i + 1))
		row.visible = i < count
		if not row.visible:
			continue
		var map_name: String = ServerNotices.map_name(reader.u32())
		var seconds: int = 0
		var instance: int = 0
		if PacketReader.wotlk:
			reader.u32()
			instance = reader.u64() & 0xFFFFFFFF
			reader.u16()
			seconds = reader.u32()
		else:
			seconds = reader.u32()
			instance = reader.u32()
		(get_node("%%RaidInfoInstance%dName" % (i + 1)) as Label).text = map_name
		(get_node("%%RaidInfoInstance%dID" % (i + 1)) as Label).text = str(instance)
		var left: Label = get_node("%%RaidInfoInstance%dReset" % (i + 1))
		left.text = "%s %s" % [WowStrings.get_text("RESETS_IN"), _reset_text(seconds)]
	if is_visible_in_tree() and count > 0:
		%RaidInfoFrame.show()


static func _reset_text(seconds: int) -> String:
	@warning_ignore("integer_division")
	var parts: Array[int] = [seconds / 86400, seconds / 3600 % 24, seconds / 60 % 60]
	var words: PackedStringArray = []
	for i: int in parts.size():
		if parts[i] > 0:
			words.append("%d %s" % [parts[i], WowStrings.get_text(RESET_UNITS[i])])
	return " ".join(words)
