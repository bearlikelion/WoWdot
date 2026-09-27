class_name CalendarFrame
extends Control

signal close_requested
signal day_hovered(button: Control, lines: PackedStringArray)
signal day_left(button: Control)
signal menu_requested(entries: Array[Dictionary], chosen: Callable)

const DAYS_SHOWN: int = 42
const WEEKDAYS: int = 7
const SECONDS_PER_DAY: int = 86400
const SECONDS_PER_HOUR: int = 3600
const MONTH_KEYS: PackedStringArray = [
	"MONTH_JANUARY", "MONTH_FEBRUARY", "MONTH_MARCH", "MONTH_APRIL", "MONTH_MAY", "MONTH_JUNE",
	"MONTH_JULY", "MONTH_AUGUST", "MONTH_SEPTEMBER", "MONTH_OCTOBER", "MONTH_NOVEMBER",
	"MONTH_DECEMBER",
]
const WEEKDAY_KEYS: PackedStringArray = [
	"WEEKDAY_SUNDAY", "WEEKDAY_MONDAY", "WEEKDAY_TUESDAY", "WEEKDAY_WEDNESDAY",
	"WEEKDAY_THURSDAY", "WEEKDAY_FRIDAY", "WEEKDAY_SATURDAY",
]
# CalendarEventType order, the types the create frame offers.
const TYPE_KEYS: PackedStringArray = [
	"CALENDAR_TYPE_RAID", "CALENDAR_TYPE_DUNGEON", "CALENDAR_TYPE_PVP", "CALENDAR_TYPE_MEETING",
	"CALENDAR_TYPE_OTHER",
]
const HOURS: int = 24
# CALENDAR_STATUS_* by Calendar.Rsvp.
const STATUS_KEYS: PackedStringArray = [
	"CALENDAR_STATUS_INVITED", "CALENDAR_STATUS_ACCEPTED", "CALENDAR_STATUS_DECLINED",
	"CALENDAR_STATUS_CONFIRMED", "CALENDAR_STATUS_OUT", "CALENDAR_STATUS_STANDBY",
	"CALENDAR_STATUS_SIGNEDUP", "CALENDAR_STATUS_NOT_SIGNEDUP", "CALENDAR_STATUS_TENTATIVE",
]
const RANK_NAME_KEYS: Dictionary[Calendar.Rank, String] = {
	Calendar.Rank.OWNER: "CALENDAR_INVITELIST_CREATORNAME",
	Calendar.Rank.MODERATOR: "CALENDAR_INVITELIST_MODERATORNAME",
}
const INVITE_ROWS: int = 20
const VIEW_ROW: String = "%CalendarViewEventInviteListScrollFrameButton"
const EDIT_ROW: String = "%CalendarCreateEventInviteListScrollFrameButton"
# CalendarCreateEventMinuteDropDown steps five minutes at a time, from the stock noon default.
const MINUTE_STEP: int = 5
const DEFAULT_HOUR: int = 12
# UIDropDownMenu_SetWidth's own padding when a caller names none, and the time pickers' overlap.
const DROP_DOWN_PADDING: float = 50.0
const TIME_OVERLAP: float = 22.0
# CALENDAR_WEEKDAY_NORMALIZED_TEX_* and CALENDAR_DAYBUTTON_NORMALIZED_TEX_* on 256 pixel atlases.
const WEEKDAY_CELL: Vector2 = Vector2(90, 28)
const WEEKDAY_TOP: float = 180.0
const DAY_CELL: float = 90.0
# The EventTexture's TexCoords: the holiday art fills this share of its texture.
const HOLIDAY_ART_SHARE: float = 0.7109375
const HOLIDAY_PATH: String = "Interface\\Calendar\\Holidays\\%s%s.blp"
# DARKDAY_TOP_TCOORDS' plain tile on CalendarShadows; the bottom half is the same tile flipped.
const DARK_TILE: Rect2 = Rect2(90, 0, 90, 45)

var viewed_month: int = 0
var viewed_year: int = 0

# The first cell's date as unix time, which each later cell steps a day from.
var _first_cell: int = 0
var _holiday_names: WowDBC
var _holiday_table: WowDBC
var _viewed_event: Dictionary = {}
var _create_date: Dictionary = {}
var _create_type: Calendar.EventType = Calendar.EventType.OTHER
# The owned event the create frame is editing, or empty while it makes a new one.
var _editing: Dictionary = {}

@onready var _calendar: Calendar = WowClient.calendar


func _ready() -> void:
	for i: int in WEEKDAYS:
		_crop(get_node("%%CalendarWeekday%dBackground" % (i + 1)), Rect2(
			Vector2((i + 1) % 2 * WEEKDAY_CELL.x, WEEKDAY_TOP), WEEKDAY_CELL
		))
		(get_node("%%CalendarWeekday%dName" % (i + 1)) as Label).text = \
				WowStrings.get_text(WEEKDAY_KEYS[i])
	for i: int in DAYS_SHOWN:
		var button: BaseButton = _day(i)
		var normal: TextureRect = button.get_node("NormalTexture")
		_crop(normal, Rect2(Vector2(randi() % 2, randi() % 2) * DAY_CELL, Vector2.ONE * DAY_CELL))
		# CalendarFrame_InitDay puts the parchment on the BACKGROUND layer, under the day's art.
		button.move_child(normal, 0)
		var prefix: String = "%%CalendarDayButton%dDarkFrame" % (i + 1)
		_crop(get_node(prefix + "Top"), DARK_TILE)
		_crop(get_node(prefix + "Bottom"), DARK_TILE)
		(get_node(prefix + "Bottom") as TextureRect).flip_v = true
		button.mouse_entered.connect(_on_day_hovered.bind(i))
		button.pressed.connect(_on_day_pressed.bind(i))
		button.gui_input.connect(_on_day_input.bind(i))
		button.mouse_exited.connect(func() -> void: day_left.emit(button))
	%CalendarPrevMonthButton.pressed.connect(_step_month.bind(-1))
	%CalendarNextMonthButton.pressed.connect(_step_month.bind(1))
	%CalendarCloseButton.pressed.connect(close_requested.emit)
	%CalendarFilterFrame.hide()
	%CalendarViewHolidayFrame.hide()
	%CalendarFrameBlocker.hide()
	for hidden: CanvasItem in [
		%CalendarViewEventFrame, %CalendarCreateEventFrame, %CalendarViewEventFrameModalOverlay,
		%CalendarCreateEventFrameModalOverlay,
	]:
		hidden.hide()
	# ponytail: 24 hour clock; no repeats, locks, auto-approve or mass invites yet.
	for unused: CanvasItem in [
		%CalendarCreateEventAMPMDropDown, %CalendarCreateEventRepeatOptionDropDown,
		%CalendarCreateEventAutoApproveCheck, %CalendarCreateEventLockEventCheck,
		%CalendarCreateEventMassInviteButton, %CalendarViewEventRemoveButton,
		%CalendarCreateEventRaidInviteButton,
		%CalendarCreateEventMassInviteButtonBorder, %CalendarCreateEventRaidInviteButtonBorder,
	]:
		unused.hide()
	# CalendarCreateEventFrame_OnLoad sizes the pickers and CalendarTitleFrame_SetText the titles.
	_set_drop_down_width(%CalendarCreateEventTypeDropDown, 100.0, DROP_DOWN_PADDING)
	var hour: Control = %CalendarCreateEventHourDropDown
	_set_drop_down_width(hour, 30.0, 40.0)
	_set_drop_down_width(%CalendarCreateEventMinuteDropDown, 30.0, 40.0)
	%CalendarCreateEventMinuteDropDown.position.x = hour.position.x + hour.size.x - TIME_OVERLAP
	%CalendarCreateEventTitleFrameText.text = WowStrings.get_text("CALENDAR_CREATE_EVENT")
	%CalendarViewEventTitleFrameText.text = WowStrings.get_text("CALENDAR_VIEW_EVENT")
	%CalendarCreateEventInviteButtonText.text = WowStrings.get_text("INVITE")
	%CalendarViewEventCloseButton.pressed.connect(%CalendarViewEventFrame.hide)
	%CalendarViewEventAcceptButton.pressed.connect(_answer.bind(Calendar.Rsvp.ACCEPTED))
	%CalendarViewEventTentativeButton.pressed.connect(_answer.bind(Calendar.Rsvp.TENTATIVE))
	%CalendarViewEventDeclineButton.pressed.connect(_answer.bind(Calendar.Rsvp.DECLINED))
	%CalendarCreateEventInviteButton.pressed.connect(_invite)
	(%CalendarCreateEventInviteEdit as LineEdit).text_submitted.connect(
		func(_text: String) -> void: _invite()
	)
	%CalendarCreateEventCloseButton.pressed.connect(%CalendarCreateEventFrame.hide)
	%CalendarCreateEventCreateButton.pressed.connect(_create)
	%CalendarCreateEventTypeDropDownButton.pressed.connect(_pick_type)
	%CalendarCreateEventHourDropDownButton.pressed.connect(_pick_hour)
	%CalendarCreateEventMinuteDropDownButton.pressed.connect(_pick_minute)
	_calendar.event_received.connect(_show_event)
	_calendar.event_updated.connect(_on_event_updated)
	WowClient.session.name_received.connect(func(_guid: int, _name: String) -> void: _fill_lists())
	_calendar.changed.connect(refresh)
	visibility_changed.connect(_on_visibility_changed)


func today() -> Dictionary:
	var now: int = _calendar.server_time
	return Time.get_date_dict_from_unix_time(now) if now else Time.get_date_dict_from_system()


# CalendarFrame_Update: the viewed month's grid, starting on the Sunday on or before the first.
func refresh() -> void:
	if not is_visible_in_tree():
		return
	%CalendarMonthName.text = WowStrings.get_text(MONTH_KEYS[viewed_month - 1])
	%CalendarYearName.text = str(viewed_year)
	var first: int = _unix(viewed_year, viewed_month, 1)
	var weekday: int = Time.get_date_dict_from_unix_time(first)["weekday"]
	_first_cell = first - weekday * SECONDS_PER_DAY
	var now: Dictionary = today()
	%CalendarTodayFrame.hide()
	for i: int in DAYS_SHOWN:
		var date: Dictionary = Time.get_date_dict_from_unix_time(_first_cell + i * SECONDS_PER_DAY)
		var prefix: String = "%%CalendarDayButton%d" % (i + 1)
		(get_node(prefix + "DateFrameDate") as Label).text = str(date["day"])
		(get_node(prefix + "DarkFrame") as CanvasItem).visible = date["month"] != viewed_month
		var is_today: bool = date["year"] == now["year"] and date["month"] == now["month"] \
				and date["day"] == now["day"]
		if is_today:
			var today_frame: Control = %CalendarTodayFrame
			today_frame.global_position = _day(i).global_position \
					+ (_day(i).size - today_frame.size) / 2.0
			today_frame.show()
		_show_day(i, date)


func _show_day(index: int, date: Dictionary) -> void:
	var prefix: String = "%%CalendarDayButton%d" % (index + 1)
	var art: TextureRect = get_node(prefix + "EventTexture")
	var holiday: Array = _holidays_on(date)
	art.visible = not holiday.is_empty()
	if art.visible:
		var texture: WowTexture = WowTexture.new()
		texture.file = HOLIDAY_PATH % [holiday[0]["texture"], holiday[0]["part"]]
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(Vector2.ZERO, texture.get_size() * HOLIDAY_ART_SHARE)
		art.texture = atlas
	var events: Array[Dictionary] = _events_on(date)
	(get_node(prefix + "EventBackgroundTexture") as CanvasItem).visible = not events.is_empty()
	var ids: Array = events.map(func(event: Dictionary) -> int: return event["id"])
	var pending: bool = _calendar.invites.any(func(invite: Dictionary) -> bool:
		return invite["status"] == Calendar.Rsvp.INVITED and invite["event"] in ids)
	(get_node(prefix + "PendingInviteTexture") as CanvasItem).visible = pending


# Each holiday running on the date, with the Start, Ongoing or End art for that day.
func _holidays_on(date: Dictionary) -> Array[Dictionary]:
	var day_start: int = _unix(date["year"], date["month"], date["day"])
	var found: Array[Dictionary] = []
	for holiday: Dictionary in _calendar.holidays:
		for packed: int in holiday["dates"]:
			if packed == 0:
				continue
			var start: Dictionary = Calendar.unpack_time(packed)
			var year: int = date["year"] if start["year"] < 0 else start["year"]
			var begins: int = _unix(year, start["month"], start["day"])
			var hours: int = maxi(holiday["durations"][0], 1)
			var ends: int = begins + (hours * SECONDS_PER_HOUR) - 1
			if day_start < begins or day_start > ends:
				continue
			var part: String = "Ongoing"
			if day_start == begins:
				part = "Start"
			elif day_start + SECONDS_PER_DAY > ends:
				part = "End"
			found.append({"id": holiday["id"], "texture": holiday["texture"], "part": part})
			break
	return found


func _events_on(date: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: Dictionary in _calendar.events:
		var time: Dictionary = event["time"]
		if time["day"] == date["day"] and time["month"] == date["month"] \
		and time["year"] == date["year"]:
			found.append(event)
	return found


func _holiday_name(holiday_id: int) -> String:
	if _holiday_table == null:
		_holiday_table = WowDBC.open(WowAssets.archive, "Holidays")
		_holiday_names = WowDBC.open(WowAssets.archive, "HolidayNames")
	var row: int = _holiday_table.find(holiday_id)
	if row < 0:
		return ""
	var name_row: int = _holiday_names.find(_holiday_table.get_uint(row, "NameID"))
	return _holiday_names.get_string(name_row, "Name") if name_row >= 0 else ""


static func _unix(year: int, month: int, day: int) -> int:
	return Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day})


static func _crop(rect: TextureRect, region: Rect2) -> void:
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = rect.texture
	atlas.region = region
	rect.texture = atlas


func _day(index: int) -> BaseButton:
	return get_node("%%CalendarDayButton%d" % (index + 1))


# UIDropDownMenu_SetWidth: the middle art takes the width and the art right of it moves along.
func _set_drop_down_width(frame: Control, width: float, padding: float) -> void:
	var middle: Control = frame.get_node(String(frame.name) + "Middle")
	var shift: float = width - middle.size.x
	middle.size.x = width
	for part: String in ["Right", "Text", "Button"]:
		(frame.get_node(String(frame.name) + part) as Control).position.x += shift
	frame.size.x = width + padding


func _date_at(index: int) -> Dictionary:
	return Time.get_date_dict_from_unix_time(_first_cell + index * SECONDS_PER_DAY)


# FULLDATE with the weekday the date falls on.
func _full_date(date: Dictionary) -> String:
	var weekday: int = Time.get_date_dict_from_unix_time(
		_unix(date["year"], date["month"], date["day"])
	)["weekday"]
	return WowStrings.format(WowStrings.get_text("FULLDATE"), [
		WowStrings.get_text(WEEKDAY_KEYS[weekday]),
		WowStrings.get_text("FULLDATE_" + MONTH_KEYS[date["month"] - 1]),
		date["day"], date["year"],
	])


# The first event of the day opens, as clicking its event button does.
func _on_day_pressed(index: int) -> void:
	var events: Array[Dictionary] = _events_on(_date_at(index))
	if not events.is_empty():
		_calendar.get_event(events[0]["id"])


# CalendarDayContextMenu: a right click offers to create an event on the day.
func _on_day_input(event: InputEvent, index: int) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT:
		return
	var date: Dictionary = _date_at(index)
	var owned: Array[Dictionary] = _events_on(date).filter(func(entry: Dictionary) -> bool:
		return _calendar.invites.any(func(invite: Dictionary) -> bool:
			return invite["event"] == entry["id"] and invite["rank"] == Calendar.Rank.OWNER))
	var entries: Array[Dictionary] = [
		{"text": WowStrings.get_text("CALENDAR_CREATE_EVENT"), "id": 0},
	]
	if not owned.is_empty():
		entries.append({"text": WowStrings.get_text("CALENDAR_DELETE_EVENT"), "id": 1})
	entries.append({"text": WowStrings.get_text("CANCEL", "Cancel")})
	menu_requested.emit(entries, func(id: int) -> void:
		if id == 0:
			_open_create(date)
		else:
			_calendar.remove_event(owned[0]["id"]))


func _open_create(date: Dictionary) -> void:
	_editing = {}
	_fill_create(date, DEFAULT_HOUR, 0, Calendar.EventType.OTHER, "", "")
	%CalendarCreateEventFrame.show()


# The stock client edits its own events in the create frame, where invites can be sent.
func _open_edit(event: Dictionary) -> void:
	_editing = event
	var time: Dictionary = event["time"]
	var type: Calendar.EventType = (
		clampi(event["type"], 0, TYPE_KEYS.size() - 1) as Calendar.EventType
	)
	_fill_create(time, time["hour"], time["minute"], type, event["title"], event["description"])
	%CalendarCreateEventFrame.show()


func _fill_create(
	date: Dictionary, hour: int, minute: int, type: Calendar.EventType, title: String,
	description: String,
) -> void:
	%CalendarViewEventFrame.hide()
	var editing: bool = not _editing.is_empty()
	_create_date = {
		"year": date["year"], "month": date["month"], "day": date["day"], "hour": hour,
		"minute": minute,
	}
	_create_type = type
	var title_edit: LineEdit = %CalendarCreateEventTitleEdit
	title_edit.text = title
	title_edit.placeholder_text = WowStrings.get_text("CALENDAR_EVENT_NAME")
	(%CalendarCreateEventDescriptionEdit as TextEdit).text = description
	var session: WowSession = WowClient.session
	%CalendarCreateEventCreatorName.text = WowStrings.format(
		WowStrings.get_text("CALENDAR_EVENT_CREATORNAME"),
		[session.get_object_name(session.get_player_guid())],
	)
	%CalendarCreateEventDateLabel.text = _full_date(date)
	%CalendarCreateEventTitleFrameText.text = WowStrings.get_text(
		"CALENDAR_EDIT_EVENT" if editing else "CALENDAR_CREATE_EVENT"
	)
	%CalendarCreateEventCreateButtonText.text = WowStrings.get_text(
		"CALENDAR_UPDATE" if editing else "CALENDAR_CREATE"
	)
	# ponytail: a new event invites only its creator; others join once it exists, as edits.
	var invite_parts: Array[CanvasItem] = [
		%CalendarCreateEventInviteEdit,
		%CalendarCreateEventInviteButton,
	]
	for invite_part: CanvasItem in invite_parts:
		invite_part.visible = editing
	(%CalendarCreateEventInviteEdit as LineEdit).text = ""
	_show_create_choices()
	_fill_lists()


func _show_create_choices() -> void:
	%CalendarCreateEventTypeDropDownText.text = WowStrings.get_text(TYPE_KEYS[_create_type])
	%CalendarCreateEventHourDropDownText.text = str(_create_date["hour"])
	%CalendarCreateEventMinuteDropDownText.text = "%02d" % _create_date["minute"]


func _pick_type() -> void:
	var entries: Array[Dictionary] = []
	for type: int in TYPE_KEYS.size():
		entries.append({
			"text": WowStrings.get_text(TYPE_KEYS[type]), "id": type,
			"checked": type == _create_type,
		})
	menu_requested.emit(entries, func(id: int) -> void:
		_create_type = id as Calendar.EventType
		_show_create_choices())


func _pick_hour() -> void:
	var entries: Array[Dictionary] = []
	for hour: int in HOURS:
		entries.append({"text": str(hour), "id": hour, "checked": hour == _create_date["hour"]})
	menu_requested.emit(entries, func(id: int) -> void:
		_create_date["hour"] = id
		_show_create_choices())


func _pick_minute() -> void:
	var entries: Array[Dictionary] = []
	for minute: int in range(0, 60, MINUTE_STEP):
		entries.append({
			"text": "%02d" % minute, "id": minute, "checked": minute == _create_date["minute"],
		})
	menu_requested.emit(entries, func(id: int) -> void:
		_create_date["minute"] = id
		_show_create_choices())


func _create() -> void:
	var title: String = (%CalendarCreateEventTitleEdit as LineEdit).text.strip_edges()
	if title.is_empty():
		return
	var description: String = (%CalendarCreateEventDescriptionEdit as TextEdit).text.strip_edges()
	if _editing.is_empty():
		_calendar.add_event(title, description, _create_type, _create_date)
	else:
		_calendar.update_event(
			_editing["id"], _my_invite(_editing).get("invite", 0), title, description,
			_create_type, _create_date,
		)
	%CalendarCreateEventFrame.hide()


func _invite() -> void:
	var edit: LineEdit = %CalendarCreateEventInviteEdit
	var player_name: String = edit.text.strip_edges()
	if player_name.is_empty() or _editing.is_empty():
		return
	_calendar.invite(_editing["id"], _my_invite(_editing).get("invite", 0), player_name)
	edit.text = ""


func _show_event(event: Dictionary) -> void:
	var session: WowSession = WowClient.session
	if event["creator"] == session.get_player_guid():
		_viewed_event = {}
		_open_edit(event)
		return
	_viewed_event = event
	_editing = {}
	%CalendarCreateEventFrame.hide()
	var time: Dictionary = event["time"]
	%CalendarViewEventTitle.text = event["title"]
	%CalendarViewEventCreatorName.text = WowStrings.format(
		WowStrings.get_text("CALENDAR_EVENT_CREATORNAME"), [session.get_object_name(event["creator"])]
	)
	%CalendarViewEventTypeName.text = WowStrings.get_text(
		TYPE_KEYS[clampi(event["type"], 0, TYPE_KEYS.size() - 1)]
	)
	%CalendarViewEventDateLabel.text = _full_date(time)
	%CalendarViewEventTimeLabel.text = "%d:%02d" % [time["hour"], time["minute"]]
	%CalendarViewEventDescription.text = event["description"]
	var invited: bool = not _my_invite(event).is_empty()
	for answer: CanvasItem in [
		%CalendarViewEventAcceptButton, %CalendarViewEventTentativeButton,
		%CalendarViewEventDeclineButton,
	]:
		answer.visible = invited
	_fill_lists()
	%CalendarViewEventFrame.show()


# Both frames list the invites; the creator and moderators wear their rank in the name.
func _fill_lists() -> void:
	_fill_invites(VIEW_ROW, _viewed_event.get("invites", []))
	_fill_invites(EDIT_ROW, _editing.get("invites", []))


func _fill_invites(prefix: String, invites: Array) -> void:
	var session: WowSession = WowClient.session
	for i: int in INVITE_ROWS:
		var row: String = prefix + str(i + 1)
		var shown: bool = i < invites.size()
		(get_node(row) as CanvasItem).visible = shown
		if not shown:
			continue
		var entry: Dictionary = invites[i]
		var player_name: String = session.get_object_name(entry["guid"])
		var rank_key: String = RANK_NAME_KEYS.get(entry["rank"], "")
		if not rank_key.is_empty():
			player_name = WowStrings.format(WowStrings.get_text(rank_key), [player_name])
		(get_node(row + "Name") as Label).text = player_name
		(get_node(row + "Class") as Label).text = ""
		(get_node(row + "Status") as Label).text = WowStrings.get_text(
			STATUS_KEYS[clampi(entry["status"], 0, STATUS_KEYS.size() - 1)]
		)
		for icon: String in ["ModIcon", "PartyIcon"]:
			(get_node(row + icon) as CanvasItem).hide()


# Invites and answers land as event packets; the open event reads itself again.
func _on_event_updated() -> void:
	var open: Dictionary = _editing if not _editing.is_empty() else _viewed_event
	if not open.is_empty() \
	and (%CalendarCreateEventFrame.visible or %CalendarViewEventFrame.visible):
		_calendar.get_event(open["id"])


func _my_invite(event: Dictionary) -> Dictionary:
	for entry: Dictionary in event.get("invites", []):
		if entry["guid"] == WowClient.session.get_player_guid():
			return entry
	return {}


func _answer(status: Calendar.Rsvp) -> void:
	var mine: Dictionary = _my_invite(_viewed_event)
	if mine.is_empty():
		return
	_calendar.rsvp(_viewed_event["id"], mine["invite"], status)
	_calendar.get_event(_viewed_event["id"])



func _step_month(direction: int) -> void:
	viewed_month += direction
	if viewed_month < 1:
		viewed_month = 12
		viewed_year -= 1
	elif viewed_month > 12:
		viewed_month = 1
		viewed_year += 1
	refresh()


func _on_day_hovered(index: int) -> void:
	var date: Dictionary = Time.get_date_dict_from_unix_time(_first_cell + index * SECONDS_PER_DAY)
	var lines: PackedStringArray = []
	for holiday: Dictionary in _holidays_on(date):
		lines.append(_holiday_name(holiday["id"]))
	for event: Dictionary in _events_on(date):
		var time: Dictionary = event["time"]
		lines.append("%s %d:%02d" % [event["title"], time["hour"], time["minute"]])
	if not lines.is_empty():
		day_hovered.emit(_day(index), lines)


func _on_visibility_changed() -> void:
	if not visible:
		return
	var now: Dictionary = today()
	viewed_month = now["month"]
	viewed_year = now["year"]
	_calendar.request()
	refresh()
