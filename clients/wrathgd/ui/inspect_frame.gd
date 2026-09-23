class_name InspectFrame
extends Control

signal close_requested
signal open_requested

# INSPECTFRAME_SUBFRAMES, one per tab.
enum SubFrame { PAPER_DOLL, PVP, TALENTS }

const ROTATE_DEGREES_PER_SECOND: float = 120.0
const TAB_OVERLAP: float = -16.0
const HONOR_COLUMN_GAP: float = 30.0
const FACTION_ICON: String = "Interface\\TargetingFrame\\UI-PVP-%s.blp"
const PORTRAIT: PackedScene = preload("res://ui/unit_portrait.tscn")
const PORTRAIT_MASK: Shader = preload("res://ui/portrait.gdshader")

var _guid: int = 0
var _worn: PackedInt32Array = []
var _slot_buttons: Dictionary[Inventory.Slot, ItemButton] = {}
var _empty_icons: Dictionary[Inventory.Slot, Texture2D] = {}
var _portrait: UnitPortrait
# MSG_INSPECT_ARENA_TEAMS by arena slot: {id, rating, games, wins, played, personal}.
var _teams: Dictionary[int, Dictionary] = {}

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
	var tabs: Array[Control] = []
	for tab: SubFrame in SubFrame.values():
		var button: BaseButton = get_node("%%InspectFrameTab%d" % (tab + 1))
		button.pressed.connect(_show_sub_frame.bind(tab))
		tabs.append(button)
	PanelManager.chain_tabs(tabs, TAB_OVERLAP)
	for i: int in PVPParentFrame.TEAM_SIZES.size():
		var data: String = "%%InspectPVPTeam%dData" % (i + 1)
		PVPParentFrame.space_around(
			get_node(data + "_"), get_node(data + "Wins"), get_node(data + "Loss")
		)
	%InspectHonorFrame.hide()
	WowClient.arena_teams.changed.connect(_show_teams)
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
	var talents: InspectTalentFrame = %InspectTalentFrame
	talents.guid = guid
	talents.clear()
	_teams.clear()
	WowClient.session.send_packet("CMSG_INSPECT", payload)
	open_requested.emit()
	_show_sub_frame(SubFrame.PAPER_DOLL)
	_refresh(true)


# InspectSwitchTabs; honor and arena teams are private, so the PvP tab asks each time it opens.
func _show_sub_frame(shown: SubFrame) -> void:
	%InspectPaperDollFrame.visible = shown == SubFrame.PAPER_DOLL
	%InspectPVPFrame.visible = shown == SubFrame.PVP
	%InspectTalentFrame.visible = shown == SubFrame.TALENTS
	for tab: SubFrame in SubFrame.values():
		PanelManager.select_tab(get_node("%%InspectFrameTab%d" % (tab + 1)), tab == shown)
	if shown != SubFrame.PVP:
		return
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(8)
	payload.encode_u64(0, _guid)
	WowClient.session.send_packet("MSG_INSPECT_HONOR_STATS", payload)
	WowClient.session.send_packet("MSG_INSPECT_ARENA_TEAMS", payload)
	_show_teams()


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


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	if opcode not in ["MSG_INSPECT_HONOR_STATS", "MSG_INSPECT_ARENA_TEAMS"]:
		return
	if reader.u64() != _guid:
		return
	if opcode == "MSG_INSPECT_HONOR_STATS":
		_show_honor(reader)
		return
	var slot: int = reader.u8()
	_teams[slot] = {
		"id": reader.u32(), "rating": reader.u32(), "games": reader.u32(), "wins": reader.u32(),
		"played": reader.u32(), "personal": reader.u32(),
	}
	_show_teams()


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


# InspectPVPHonor_Update: today's and yesterday's kills share one word, sixteen bits each.
func _show_honor(reader: PacketReader) -> void:
	reader.u8()
	var kills: int = reader.u32()
	%InspectPVPHonorTodayKills.text = str(kills & 0xFFFF)
	%InspectPVPHonorYesterdayKills.text = str((kills >> 16) & 0xFFFF)
	%InspectPVPHonorTodayHonor.text = str(reader.u32())
	%InspectPVPHonorYesterdayHonor.text = str(reader.u32())
	%InspectPVPHonorLifetimeKills.text = str(reader.u32())
	for hidden: CanvasItem in [%InspectPVPFrameHonorPoints, %InspectPVPFrameArenaPoints]:
		hidden.hide()
	var session: WowSession = WowClient.session
	var race: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_BYTES_0") & 0xFF
	%InspectPVPFrameHonorIcon.texture = PVPParentFrame.load_texture(
		FACTION_ICON % ("Alliance" if CharacterOptions.faction(race) \
				== CharacterOptions.Faction.ALLIANCE else "Horde")
	)
	_lay_out_honor()


# Each column's label sits past the one before it, which only its text width places.
func _lay_out_honor() -> void:
	var x: float = %InspectPVPHonorTodayLabel.position.x
	for column: String in ["Today", "Yesterday", "Lifetime"]:
		var label: Label = get_node("%InspectPVPHonor" + column + "Label")
		label.size.x = label.get_combined_minimum_size().x
		label.position.x = x
		var center: float = x + label.size.x / 2.0
		for value: String in ["Kills", "Honor"]:
			var number: Label = get_node("%InspectPVPHonor" + column + value)
			number.offset_left = center
			number.offset_right = center
		x += label.size.x + HONOR_COLUMN_GAP
	for prefix: String in ["%InspectPVPFrameHonor", "%InspectPVPFrameArena"]:
		PVPParentFrame.place_after(
			get_node(prefix + "Icon"), get_node(prefix + "Label"), PVPParentFrame.ICON_GAP
		)


# InspectPVPTeam_Update: the arena slots count 2v2, 3v3 and 5v5 from 0.
func _show_teams() -> void:
	if not %InspectPVPFrame.is_visible_in_tree():
		return
	for i: int in PVPParentFrame.TEAM_SIZES.size():
		var team_size: int = PVPParentFrame.TEAM_SIZES[i]
		var prefix: String = "%%InspectPVPTeam%d" % (i + 1)
		var stats: Dictionary = _teams.get(i, {})
		var team: Dictionary = WowClient.arena_teams.teams.get(stats.get("id", 0), {})
		if stats and not team.has("name"):
			WowClient.arena_teams.query(stats["id"])
		var shown: bool = team.has("name")
		(get_node(prefix) as CanvasItem).modulate.a = \
				1.0 if shown else PVPParentFrame.EMPTY_TEAM_ALPHA
		(get_node(prefix + "Data") as CanvasItem).visible = shown
		(get_node(prefix + "Standard") as CanvasItem).modulate.a = \
				1.0 if shown else PVPParentFrame.EMPTY_STANDARD_ALPHA
		(get_node(prefix + "StandardBorder") as CanvasItem).visible = shown
		(get_node(prefix + "StandardEmblem") as CanvasItem).visible = shown
		var type_label: Label = get_node(prefix + "TeamType")
		type_label.visible = not shown
		type_label.text = WowStrings.get_text("PVP_TEAMSIZE") % [team_size, team_size]
		var banner: TextureRect = get_node(prefix + "StandardBanner")
		banner.texture = PVPParentFrame.load_texture(PVPParentFrame.BANNER % team_size)
		var background: int = team.get("background", 0xFFFFFF)
		banner.self_modulate = PVPParentFrame.team_color(background) if shown else Color.WHITE
		if not shown:
			continue
		(get_node(prefix + "DataTypeLabel") as Label).text = \
				WowStrings.get_text("ARENA_THIS_SEASON")
		(get_node(prefix + "DataName") as Label).text = team["name"]
		(get_node(prefix + "DataRating") as Label).text = str(stats["rating"])
		(get_node(prefix + "DataGames") as Label).text = str(stats["games"])
		(get_node(prefix + "DataWins") as Label).text = str(stats["wins"])
		(get_node(prefix + "DataLoss") as Label).text = str(stats["games"] - stats["wins"])
		(get_node(prefix + "DataPlayed") as Label).text = str(stats["personal"])
		(get_node(prefix + "DataPlayedLabel") as Label).text = WowStrings.get_text("RATING")
		var border: TextureRect = get_node(prefix + "StandardBorder")
		border.texture = PVPParentFrame.load_texture(
			PVPParentFrame.BANNER_BORDER % [team_size, team["border"]]
		)
		border.self_modulate = PVPParentFrame.team_color(team["border_color"])
		var emblem: TextureRect = get_node(prefix + "StandardEmblem")
		emblem.texture = PVPParentFrame.load_texture(PVPParentFrame.EMBLEM % team["emblem"])
		emblem.self_modulate = PVPParentFrame.team_color(team["emblem_color"])
