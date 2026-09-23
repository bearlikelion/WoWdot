class_name CalendarFrame
extends Control

signal close_requested
signal day_hovered(button: Control, lines: PackedStringArray)
signal day_left(button: Control)

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
		button.mouse_exited.connect(func() -> void: day_left.emit(button))
	%CalendarPrevMonthButton.pressed.connect(_step_month.bind(-1))
	%CalendarNextMonthButton.pressed.connect(_step_month.bind(1))
	%CalendarCloseButton.pressed.connect(close_requested.emit)
	%CalendarFilterFrame.hide()
	%CalendarViewHolidayFrame.hide()
	%CalendarFrameBlocker.hide()
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
