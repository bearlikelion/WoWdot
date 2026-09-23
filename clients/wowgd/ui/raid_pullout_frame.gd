class_name RaidPulloutFrame
extends WowButton

signal unit_selected(guid: int)
signal menu_requested(entries: Array[Dictionary], chosen: Callable)

enum MenuItem { SHOW_BUFFS = 1, SHOW_DEBUFFS, HIDE_BACKGROUND, CLOSE }

const BUTTON: PackedScene = preload("res://ui/raid_pullout_button.tscn")
# RaidPullout_Update: buttons stack 33 apart from 10 below the top, with 14 of border in all.
const BUTTON_HEIGHT: float = 33.0
const FIRST_BUTTON_TOP: float = 10.0
const BUTTON_INSET: float = 1.0
const BORDER: float = 14.0
# ponytail: redraws on a timer, where the stock frame listens for UNIT_HEALTH and UNIT_AURA.
const REFRESH_SECONDS: float = 0.25

var group: int = -1

var _show_buffs: bool = false
var _buttons: Array[RaidPulloutButton] = []
var _moving: bool = false
var _grab: Vector2 = Vector2.ZERO
var _since_refresh: float = 0.0

@onready var _backdrop: CanvasItem = $MenuBackdrop


func _ready() -> void:
	super()
	# The template centres itself; a pullout goes wherever it is dropped.
	set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	($DropDown as CanvasItem).hide()
	gui_input.connect(_on_gui_input)


func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh >= REFRESH_SECONDS:
		refresh()


func _input(event: InputEvent) -> void:
	if not _moving:
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion:
		_place(motion.position - _grab)
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click and click.button_index == MOUSE_BUTTON_LEFT and not click.pressed:
		_moving = false


# RaidPullout_GenerateGroupFrame: the pullout takes the group and hangs its top from the cursor.
func show_group(index: int) -> void:
	group = index
	($Name as Label).text = "%s %d" % [WowStrings.get_text("GROUP"), index + 1]
	refresh()
	if visible:
		begin_move(Vector2(size.x / 2.0, 0.0))


func begin_move(grab: Vector2) -> void:
	_grab = grab
	_moving = true
	_place(get_viewport().get_mouse_position() - _grab)


func refresh() -> void:
	_since_refresh = 0.0
	var entries: Array[Dictionary] = _members()
	visible = not entries.is_empty()
	if not visible:
		return
	while _buttons.size() < entries.size():
		var button: RaidPulloutButton = BUTTON.instantiate()
		add_child(button)
		button.unit_selected.connect(unit_selected.emit)
		button.menu_requested.connect(_open_menu)
		_buttons.append(button)
	for i: int in _buttons.size():
		_buttons[i].visible = i < entries.size()
		if not _buttons[i].visible:
			continue
		_buttons[i].position = Vector2(
			(size.x - _buttons[i].size.x) / 2.0 + BUTTON_INSET, FIRST_BUTTON_TOP + i * BUTTON_HEIGHT
		)
		_buttons[i].show_member(
			entries[i], PartyFrame.member_stats.get(entries[i]["guid"], {}), _show_buffs
		)
	size.y = entries.size() * BUTTON_HEIGHT + BORDER


# RAID_SUBGROUP_LISTS for this group: the other members in it, and the player when it is theirs.
func _members() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if group < 0 or not PartyFrame.is_raid:
		return entries
	var session: WowSession = WowClient.session
	if PartyFrame.own_subgroup == group:
		var me: int = session.get_player_guid()
		entries.append({"name": session.get_object_name(me), "guid": me, "online": true})
	for member: Dictionary in PartyFrame.members:
		if member["subgroup"] == group:
			entries.append(member)
	return entries


# clampedToScreen, in viewport space so the UI scale does not matter.
func _place(at: Vector2) -> void:
	var drawn: Vector2 = get_global_rect().size
	global_position = at.clamp(Vector2.ZERO, (get_viewport_rect().size - drawn).max(Vector2.ZERO))


# RaidPulloutDropDown_Initialize: buffs or debuffs, the background, and closing the pullout.
func _open_menu() -> void:
	var entries: Array[Dictionary] = [
		{"text": WowStrings.get_text("SHOW_BUFFS"), "id": MenuItem.SHOW_BUFFS},
		{"text": WowStrings.get_text("SHOW_DEBUFFS"), "id": MenuItem.SHOW_DEBUFFS},
		{"text": WowStrings.get_text("HIDE_PULLOUT_BG"), "id": MenuItem.HIDE_BACKGROUND},
		{"text": WowStrings.get_text("CLOSE"), "id": MenuItem.CLOSE},
	]
	menu_requested.emit(entries, func(id: int) -> void:
		match id as MenuItem:
			MenuItem.SHOW_BUFFS:
				_show_buffs = true
			MenuItem.SHOW_DEBUFFS:
				_show_buffs = false
			MenuItem.HIDE_BACKGROUND:
				_backdrop.visible = not _backdrop.visible
			MenuItem.CLOSE:
				group = -1
				hide()
				return
		refresh()
	)


func _on_gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null:
		return
	if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
		begin_move(click.position)
	elif click.button_index == MOUSE_BUTTON_RIGHT and not click.pressed:
		_open_menu()
