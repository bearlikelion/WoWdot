class_name ReputationFrame
extends Control

signal watched_changed(entry: Dictionary)
signal message_added(text: String)

const NUM_FACTIONS_DISPLAYED: int = 15
const REPUTATIONFRAME_FACTIONHEIGHT: float = 26.0
const BASE_SLOTS: int = 4
# SMSG_INITIALIZE_FACTIONS flag bits.
const FLAG_VISIBLE: int = 0x01
const FLAG_AT_WAR: int = 0x02
const FLAG_HIDDEN: int = 0x04
const FLAG_INVISIBLE_FORCED: int = 0x08
const FLAG_INACTIVE: int = 0x20
# Where each standing from Hated to Exalted begins, and where Exalted ends.
const STANDING_FLOORS: Array[int] = [-42000, -6000, -3000, 0, 3000, 9000, 21000, 42000, 43000]
# FACTION_BAR_COLORS, Hated first.
const BAR_COLORS: Array[Color] = [
	Color(0.8, 0.3, 0.22), Color(0.8, 0.3, 0.22), Color(0.75, 0.27, 0.0), Color(0.9, 0.7, 0.0),
	Color(0.0, 0.6, 0.1), Color(0.0, 0.6, 0.1), Color(0.0, 0.6, 0.1), Color(0.0, 0.6, 0.1),
]
const PLUS_BUTTON: String = "Interface\\Buttons\\UI-PlusButton-Up.blp"
const MINUS_BUTTON: String = "Interface\\Buttons\\UI-MinusButton-Up.blp"
const INACTIVE_HEADER: int = -1

# GetFactionInfo rows: parent faction headers, each followed by its factions unless collapsed.
var _entries: Array[Dictionary] = []
var _collapsed: Dictionary[int, bool] = {}
var _selected: int = -1
var _toggled: Dictionary[int, int] = {}
var _offset: int = 0
var _factions: WowDBC
var _watched: int = -1
var _textures: Dictionary[String, WowTexture] = {}

@onready var _list_scroll: WowScrollFrame = %ReputationListScrollFrame
@onready var _detail: Control = %ReputationDetailFrame


func _ready() -> void:
	_factions = WowDBC.open(WowAssets.archive, "Faction")
	for path: String in [PLUS_BUTTON, MINUS_BUTTON]:
		var texture: WowTexture = WowTexture.new()
		texture.file = path
		_textures[path] = texture
	for i: int in NUM_FACTIONS_DISPLAYED:
		var bar: TextureProgressBar = _bar(i)
		bar.mouse_filter = Control.MOUSE_FILTER_STOP
		bar.gui_input.connect(_on_bar_input.bind(i))
		bar.mouse_entered.connect(_on_bar_hovered.bind(i, true))
		bar.mouse_exited.connect(_on_bar_hovered.bind(i, false))
		_expand_button(i).pressed.connect(_on_header_pressed.bind(i))
	%ReputationDetailCloseButton.pressed.connect(_detail.hide)
	%ReputationDetailAtWarCheckBox.pressed.connect(
		_on_flag_pressed.bind("CMSG_SET_FACTION_ATWAR", FLAG_AT_WAR)
	)
	%ReputationDetailInactiveCheckBox.pressed.connect(
		_on_flag_pressed.bind("CMSG_SET_FACTION_INACTIVE", FLAG_INACTIVE)
	)
	%ReputationDetailMainScreenCheckBox.pressed.connect(_on_watch_pressed)
	(%ReputationDetailFactionDescription as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list_scroll.scrolled.connect(_on_list_scrolled)
	WowClient.session.factions_changed.connect(_on_factions_changed)
	WowClient.session.faction_standing_changed.connect(_on_standing_changed)
	WowClient.session.object_updated.connect(_on_object_updated)
	visibility_changed.connect(refresh)
	_update_watch()


func _gui_input(event: InputEvent) -> void:
	var wheel: InputEventMouseButton = event as InputEventMouseButton
	if wheel == null or not wheel.pressed:
		return
	if wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		accept_event()
		var up: bool = wheel.button_index == MOUSE_BUTTON_WHEEL_UP
		var step: float = -REPUTATIONFRAME_FACTIONHEIGHT if up else REPUTATIONFRAME_FACTIONHEIGHT
		_list_scroll.scroll_to(_list_scroll.scroll() + step)


# ReputationFrame_Update.
func refresh() -> void:
	if not is_visible_in_tree():
		return
	_build_entries()
	var hidden_entries: int = maxi(_entries.size() - NUM_FACTIONS_DISPLAYED, 0)
	_list_scroll.visible = hidden_entries > 0
	_list_scroll.set_range(hidden_entries * REPUTATIONFRAME_FACTIONHEIGHT)
	_offset = mini(_offset, hidden_entries)
	for i: int in NUM_FACTIONS_DISPLAYED:
		var index: int = i + _offset
		var row: Control = get_node("%%ReputationBar%d" % (i + 1))
		var bar: TextureProgressBar = _bar(i)
		var expand: TextureButton = _expand_button(i)
		row.visible = index < _entries.size()
		if not row.visible:
			continue
		var entry: Dictionary = _entries[index]
		expand.visible = entry["header"]
		bar.visible = not entry["header"]
		(get_node("%%ReputationBar%dFactionName" % (i + 1)) as Label).text = entry["name"]
		if entry["header"]:
			var normal: TextureRect = expand.get_node("NormalTexture")
			normal.texture = _textures[PLUS_BUTTON if entry["collapsed"] else MINUS_BUTTON]
			continue
		_show_faction(i, entry)
	if _selected < 0:
		_detail.hide()


func _show_faction(i: int, entry: Dictionary) -> void:
	var bar: TextureProgressBar = _bar(i)
	var standing_id: int = entry["standing_id"]
	_standing(i).text = _standing_label(standing_id)
	bar.min_value = 0.0
	bar.max_value = entry["bar_max"]
	bar.value = entry["bar_value"]
	bar.tint_progress = BAR_COLORS[standing_id - 1]
	if entry["index"] == _selected and _detail.visible:
		%ReputationDetailFactionName.text = entry["name"]
		%ReputationDetailFactionDescription.text = entry["description"]
		(%ReputationDetailAtWarCheckBox as WowButton).checked = entry["at_war"]
		(%ReputationDetailInactiveCheckBox as WowButton).checked = entry["inactive"]


# The server takes the change without answering, so the flag is flipped here until the next login.
func _on_flag_pressed(opcode: String, flag: int) -> void:
	if _selected < 0:
		return
	_toggled[_selected] = _toggled.get(_selected, 0) ^ flag
	var flags_now: int = WowClient.session.get_faction_flags()[_selected] ^ _toggled[_selected]
	var set_now: bool = flags_now & flag != 0
	var payload: PackedByteArray = []
	payload.resize(5)
	payload.encode_u32(0, _selected)
	payload.encode_u8(4, 1 if set_now else 0)
	WowClient.session.send_packet(opcode, payload)
	refresh()


# The factions the server marked visible under their parent faction, with inactive ones last.
func _build_entries() -> void:
	var session: WowSession = WowClient.session
	var flags: PackedByteArray = session.get_faction_flags()
	var standings: PackedInt32Array = session.get_faction_standings()
	var bytes_0: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_BYTES_0")
	var race_bit: int = 1 << ((bytes_0 & 0xFF) - 1)
	var class_bit: int = 1 << (((bytes_0 >> 8) & 0xFF) - 1)
	var by_header: Dictionary[int, Array] = {}
	for row: int in _factions.row_count():
		var index: int = _factions.get_int(row, "ReputationIndex")
		if index < 0 or index >= flags.size():
			continue
		var faction_flags: int = flags[index] ^ _toggled.get(index, 0)
		if faction_flags & FLAG_VISIBLE == 0 or faction_flags & (FLAG_HIDDEN | FLAG_INVISIBLE_FORCED):
			continue
		var value: int = _base_reputation(row, race_bit, class_bit) + standings[index]
		var standing_id: int = _standing_id(value)
		var inactive: bool = faction_flags & FLAG_INACTIVE != 0
		var header: int = INACTIVE_HEADER if inactive else _factions.get_uint(row, "ParentFactionID")
		if not by_header.has(header):
			by_header[header] = []
		by_header[header].append({
			"header": false, "index": index, "name": _factions.get_string(row, "Name"),
			"description": _factions.get_string(row, "Description"),
			"standing_id": standing_id, "at_war": faction_flags & FLAG_AT_WAR != 0,
			"inactive": inactive,
			"bar_max": STANDING_FLOORS[standing_id] - STANDING_FLOORS[standing_id - 1],
			"bar_value": value - STANDING_FLOORS[standing_id - 1],
		})
	var headers: Array[int] = []
	headers.assign(by_header.keys())
	headers.sort_custom(func(a: int, b: int) -> bool:
		if (a == INACTIVE_HEADER) != (b == INACTIVE_HEADER):
			return b == INACTIVE_HEADER
		return _header_name(a) < _header_name(b)
	)
	_entries.clear()
	for header: int in headers:
		var collapsed: bool = _collapsed.has(header)
		_entries.append({
			"header": true, "id": header, "name": _header_name(header), "collapsed": collapsed,
		})
		if collapsed:
			continue
		var factions: Array = by_header[header]
		factions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
		_entries.append_array(factions)


# The faction shown on the main bar, or an empty dictionary when none is watched.
func watched_entry() -> Dictionary:
	for entry: Dictionary in _entries:
		if not entry["header"] and entry["index"] == _watched:
			return entry
	return {}


func _on_factions_changed() -> void:
	refresh()
	_update_watch()


func _on_standing_changed(index: int, delta: int) -> void:
	for row: int in _factions.row_count():
		if _factions.get_int(row, "ReputationIndex") == index:
			var key: String = "FACTION_STANDING_INCREASED" if delta > 0 \
					else "FACTION_STANDING_DECREASED"
			var faction_name: String = _factions.get_string(row, "Name")
			message_added.emit(WowStrings.get_text(key) % [faction_name, absi(delta)])
			return


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid() and _watched_index() != _watched:
		_update_watch()


func _update_watch() -> void:
	_watched = _watched_index()
	_build_entries()
	%ReputationDetailMainScreenCheckBox.checked = _watched >= 0 and _watched == _selected
	watched_changed.emit(watched_entry())


func _watched_index() -> int:
	var session: WowSession = WowClient.session
	var value: int = session.get_field(session.get_player_guid(), "PLAYER_FIELD_WATCHED_FACTION_INDEX")
	return value - 0x100000000 if value >= 0x80000000 else value


# CMSG_SET_WATCHED_FACTION takes the reputation index, or -1 to clear the bar.
func _on_watch_pressed() -> void:
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_s32(0, -1 if _watched == _selected else _selected)
	WowClient.session.send_packet("CMSG_SET_WATCHED_FACTION", payload)


# The starting reputation a race and class have with a faction, before anything earned.
func _base_reputation(row: int, race_bit: int, class_bit: int) -> int:
	for i: int in BASE_SLOTS:
		var races: int = _factions.get_uint(row, "ReputationRaceMask%d" % i)
		var classes: int = _factions.get_uint(row, "ReputationClassMask%d" % i)
		var race_matches: bool = races & race_bit != 0 or (races == 0 and classes != 0)
		if race_matches and (classes == 0 or classes & class_bit != 0):
			return _factions.get_int(row, "ReputationBase%d" % i)
	return 0


func _standing_id(value: int) -> int:
	for i: int in range(STANDING_FLOORS.size() - 2, -1, -1):
		if value >= STANDING_FLOORS[i]:
			return i + 1
	return 1


func _standing_label(standing_id: int) -> String:
	var session: WowSession = WowClient.session
	var bytes_0: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_BYTES_0")
	var key: String = "FACTION_STANDING_LABEL%d" % standing_id
	return WowStrings.get_text(key + "_FEMALE" if (bytes_0 >> 16) & 0xFF == 1 else key)


func _header_name(header: int) -> String:
	if header == INACTIVE_HEADER:
		return WowStrings.get_text("FACTION_INACTIVE")
	var row: int = _factions.find(header)
	return _factions.get_string(row, "Name") if row >= 0 else ""


func _bar(index: int) -> TextureProgressBar:
	return get_node("%%ReputationBar%dReputationBar" % (index + 1))


func _expand_button(index: int) -> TextureButton:
	return get_node("%%ReputationBar%dExpandOrCollapseButton" % (index + 1))


func _standing(index: int) -> Label:
	return get_node("%%ReputationBar%dReputationBarFactionStanding" % (index + 1))


func _on_header_pressed(index: int) -> void:
	var header: int = _entries[index + _offset]["id"]
	if _collapsed.has(header):
		_collapsed.erase(header)
	else:
		_collapsed[header] = true
	refresh()


# ReputationBar_OnClick: a second click on the selected faction closes its details.
func _on_bar_input(event: InputEvent, index: int) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var faction: int = _entries[index + _offset]["index"]
	if _detail.visible and faction == _selected:
		_detail.hide()
	else:
		_selected = faction
		_detail.show()
	refresh()


# The bar's standing swaps for its progress while the mouse is over it.
func _on_bar_hovered(index: int, hovered: bool) -> void:
	if index + _offset >= _entries.size():
		return
	var entry: Dictionary = _entries[index + _offset]
	if entry["header"]:
		return
	_standing(index).text = "%d / %d" % [entry["bar_value"], entry["bar_max"]] if hovered \
	else _standing_label(entry["standing_id"])


func _on_list_scrolled(value: float) -> void:
	var offset: int = roundi(value / REPUTATIONFRAME_FACTIONHEIGHT)
	if offset != _offset:
		_offset = offset
		refresh()
