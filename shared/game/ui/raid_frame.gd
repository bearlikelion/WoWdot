class_name RaidFrame
extends Control

const GROUP: PackedScene = preload("res://ui/raid_group.tscn")
const MEMBER: PackedScene = preload("res://ui/raid_group_button.tscn")
const GROUPS: int = 8
const SLOTS: int = 5
# RaidGroup1 sits here; the rest run two to a row, as the stock anchors chain them.
const FIRST_GROUP: Vector2 = Vector2(16.0, 70.0)
const COLUMN_GAP: float = 3.0
const ROW_GAP: float = 14.0
const OFFLINE_COLOR: Color = Color(0.5, 0.5, 0.5)

var _groups: Array[Control] = []
var _buttons: Array[Control] = []


func _ready() -> void:
	for i: int in GROUPS:
		var group: Control = GROUP.instantiate()
		add_child(group)
		group.position = FIRST_GROUP + Vector2(
			(i % 2) * (group.size.x + COLUMN_GAP), (i / 2) * (group.size.y + ROW_GAP)
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
	# ponytail: adding by name needs the name popup; /invite does the same meanwhile.
	%RaidFrameAddMemberButton.hide()
	# ponytail: saved instances (SMSG_RAID_INSTANCE_INFO) print to chat; the info window waits.
	%RaidFrameRaidInfoButton.hide()
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
	var convert: BaseButton = %RaidFrameConvertToRaidButton
	convert.visible = not raid
	convert.disabled = not PartyFrame.in_party() or PartyFrame.leader != session.get_player_guid()
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
func _on_packet_received(opcode: String, _payload: PackedByteArray) -> void:
	if opcode == "SMSG_GROUP_LIST":
		refresh.call_deferred()
