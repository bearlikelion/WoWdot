class_name InspectFrame
extends Control

signal close_requested
signal open_requested

const ROTATE_DEGREES_PER_SECOND: float = 120.0
const PORTRAIT: PackedScene = preload("res://ui/unit_portrait.tscn")
const PORTRAIT_MASK: Shader = preload("res://ui/portrait.gdshader")

var _guid: int = 0
var _worn: PackedInt32Array = []
var _slot_buttons: Dictionary[Inventory.Slot, ItemButton] = {}
var _empty_icons: Dictionary[Inventory.Slot, Texture2D] = {}
var _portrait: UnitPortrait

@onready var _model: WowModelFrame = %InspectModelFrameModel
@onready var _rotate_left: BaseButton = %InspectModelRotateLeftButton
@onready var _rotate_right: BaseButton = %InspectModelRotateRightButton


func _ready() -> void:
	for slot_name: String in CharacterFrame.SLOTS:
		var slot: Inventory.Slot = CharacterFrame.SLOTS[slot_name][0]
		var button: ItemButton = get_node("%Inspect" + slot_name + "Slot")
		var empty: WowTexture = WowTexture.new()
		empty.file = CharacterFrame.EMPTY_SLOT % CharacterFrame.SLOTS[slot_name][1]
		_slot_buttons[slot] = button
		_empty_icons[slot] = empty
		button.mouse_entered.connect(_on_slot_hovered.bind(slot))
		button.mouse_exited.connect(_on_slot_left.bind(slot))
	%InspectFrameCloseButton.pressed.connect(close_requested.emit)
	# The paper doll's art is declared after these and would draw over them.
	for above: Control in [%InspectNameFrame, %InspectFrameCloseButton]:
		move_child(above, -1)
	%InspectFrameTab1.pressed.connect(_show_honor.bind(false))
	%InspectFrameTab2.pressed.connect(_show_honor.bind(true))
	%InspectHonorFrame.hide()
	_portrait = PORTRAIT.instantiate()
	add_child(_portrait)
	var mask: ShaderMaterial = ShaderMaterial.new()
	mask.shader = PORTRAIT_MASK
	%InspectFramePortrait.material = mask
	%InspectFramePortrait.texture = _portrait.get_texture()
	var session: WowSession = WowClient.session
	session.object_updated.connect(_on_object_updated)
	session.item_info_received.connect(func(_entry: int) -> void: _refresh(true))
	session.objects_destroyed.connect(_on_objects_destroyed)
	session.packet_received.connect(_on_packet_received)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var turn: float = float(_rotate_right.button_pressed) - float(_rotate_left.button_pressed)
	_model.facing += turn * ROTATE_DEGREES_PER_SECOND * delta


# InspectUnit: the server is told, though 1.12 shows everything from the fields it already sent.
func inspect(guid: int) -> void:
	_guid = guid
	_worn = []
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(8)
	payload.encode_u64(0, guid)
	WowClient.session.send_packet("CMSG_INSPECT", payload)
	open_requested.emit()
	_show_honor(false)
	_refresh(true)


# The honor numbers are private fields, so the server is asked for them each time the tab opens.
func _show_honor(honor: bool) -> void:
	%InspectPaperDollFrame.visible = not honor
	%InspectHonorFrame.visible = honor
	if honor:
		var payload: PackedByteArray = PackedByteArray()
		payload.resize(8)
		payload.encode_u64(0, _guid)
		WowClient.session.send_packet("MSG_INSPECT_HONOR_STATS", payload)


func _refresh(redress: bool) -> void:
	var session: WowSession = WowClient.session
	if not is_visible_in_tree() or not session.has_object(_guid):
		return
	var bytes_0: int = session.get_field(_guid, "UNIT_FIELD_BYTES_0")
	%InspectNameText.text = session.get_object_name(_guid)
	%InspectLevelText.text = WowStrings.get_text("PLAYER_LEVEL") % [
		session.get_field(_guid, "UNIT_FIELD_LEVEL"),
		CharacterOptions.race_name(bytes_0 & 0xFF),
		CharacterOptions.class_label((bytes_0 >> 8) & 0xFF),
	]
	%InspectTitleText.hide()
	%InspectGuildText.hide()
	var worn: PackedInt32Array = CharacterModels.visible_items(session, _guid)
	for slot: Inventory.Slot in _slot_buttons:
		var icon: Texture2D = Inventory.icon(worn[slot]) if worn[slot] != 0 else null
		_slot_buttons[slot].set_item(icon if icon else _empty_icons[slot])
	if worn == _worn and not redress:
		return
	_worn = worn
	_portrait.show_unit(_guid)
	var display: int = session.get_field(_guid, "UNIT_FIELD_DISPLAYID")
	var look: Dictionary = CharacterModels.player_look(session, _guid)
	_model.frame_character(WowAssets.creatures.instantiate(display, look))


# Each sixteen bit kill count is followed by a dead word the 1.12 client skips.
func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "MSG_INSPECT_HONOR_STATS":
		return
	var reader: PacketReader = PacketReader.new(payload)
	if reader.u64() != _guid:
		return
	var session: WowSession = WowClient.session
	var race: int = session.get_field(_guid, "UNIT_FIELD_BYTES_0") & 0xFF
	var alliance: bool = CharacterOptions.faction(race) == CharacterOptions.Faction.ALLIANCE
	%InspectHonorFrameLifeTimeRankValue.text = HonorFrame.rank_name(reader.u8(), alliance)
	var today: int = reader.u32()
	%InspectHonorFrameCurrentHKValue.text = str(today & 0xFFFF)
	%InspectHonorFrameCurrentDKValue.text = str((today >> 16) & 0xFFFF)
	for label: String in ["Yesterday", "LastWeek", "ThisWeek"]:
		(get_node("%%InspectHonorFrame%sHKValue" % label) as Label).text = str(reader.u16())
		reader.u16()
	%InspectHonorFrameLifeTimeHKValue.text = str(reader.u32())
	%InspectHonorFrameLifeTimeDKValue.text = str(reader.u32())
	for label: String in ["Yesterday", "LastWeek", "ThisWeek"]:
		(get_node("%%InspectHonorFrame%sContributionValue" % label) as Label).text = str(reader.u32())
	%InspectHonorFrameLastWeekStandingValue.text = str(reader.u32())
	var bar: TextureProgressBar = %InspectHonorFrameProgressBar
	bar.max_value = 255.0
	bar.value = reader.u8()
	bar.tint_progress = HonorFrame.ALLIANCE_BAR if alliance else HonorFrame.HORDE_BAR
	var rank: int = (session.get_field(_guid, "PLAYER_BYTES_3") >> 24) & 0xFF
	var number: int = maxi(rank - HonorFrame.RANK_OFFSET, 0)
	%InspectHonorFrameCurrentPVPTitle.text = HonorFrame.rank_name(rank, alliance)
	%InspectHonorFrameCurrentPVPRank.text = "(%s %d)" % [WowStrings.get_text("RANK"), number]
	HonorFrame.center_rank.call_deferred(
		%InspectHonorFrameCurrentPVPTitle, %InspectHonorFrameCurrentPVPRank, size.x
	)
	var badge: TextureRect = %InspectHonorFramePvPIcon
	badge.visible = number > 0
	if number > 0:
		var texture: WowTexture = WowTexture.new()
		texture.file = HonorFrame.RANK_BADGE % number
		badge.texture = texture


func _on_slot_hovered(slot: Inventory.Slot) -> void:
	if GameTooltip.current and slot < _worn.size() and _worn[slot] != 0:
		GameTooltip.current.set_item(_slot_buttons[slot], _worn[slot])


func _on_slot_left(slot: Inventory.Slot) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(_slot_buttons[slot])


func _on_object_updated(guid: int) -> void:
	if guid == _guid:
		_refresh(false)


# The stock window closes when its unit leaves sight.
func _on_objects_destroyed(guids: PackedInt64Array) -> void:
	if _guid != 0 and guids.has(_guid) and is_visible_in_tree():
		close_requested.emit()
