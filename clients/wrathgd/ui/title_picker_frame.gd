class_name TitlePickerFrame
extends Control

signal title_chosen(text: String)

const SHOWN: int = 6
const KNOWN_TITLE_FIELDS: int = 6
# PlayerTitleFrame's None entry, which clears the chosen title.
const NO_TITLE: int = -1

# Each known title as {bit, name}, None first and the rest by name.
var titles: Array[Dictionary] = []

var _offset: int = 0

@onready var _scroll: WowScrollFrame = %PlayerTitlePickerScrollFrame


func _ready() -> void:
	for i: int in SHOWN:
		_button(i).pressed.connect(_on_button_pressed.bind(i))
	_scroll.faux = true
	_scroll.scrolled.connect(_on_scrolled)


# PlayerTitleFrame_UpdateTitles: the known titles and the text the dropdown shows.
func refresh() -> String:
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	var female: bool = (session.get_field(guid, "UNIT_FIELD_BYTES_0") >> 16) & 0xFF == 1
	var known_first: int = session.field_index("PLAYER__FIELD_KNOWN_TITLES")
	var chosen: int = session.get_field(guid, "PLAYER_CHOSEN_TITLE")
	var table: WowDBC = WowDBC.open(WowAssets.archive, "CharTitles")
	titles.clear()
	var chosen_name: String = WowStrings.get_text("NONE")
	for row: int in table.row_count():
		var bit: int = table.get_uint(row, "TitleBit")
		var field: int = floori(bit / 32.0)
		if field >= KNOWN_TITLE_FIELDS \
		or session.get_field(guid, known_first + field) & (1 << (bit % 32)) == 0:
			continue
		var title: String = table.get_string(row, "TitleFemale" if female else "Title")
		title = title.replace("%s", "").strip_edges()
		titles.append({"bit": bit, "name": title})
		if bit == chosen:
			chosen_name = title
	titles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
	titles.push_front({"bit": NO_TITLE, "name": WowStrings.get_text("NONE")})
	_scroll.set_range(maxi(titles.size() - SHOWN, 0))
	_update()
	if titles.size() < 2:
		return ""
	return chosen_name if chosen else WowStrings.get_text("PAPERDOLL_SELECT_TITLE")


func _update() -> void:
	var chosen: int = WowClient.session.get_field(
		WowClient.session.get_player_guid(), "PLAYER_CHOSEN_TITLE"
	)
	for i: int in SHOWN:
		var index: int = _offset + i
		var button: BaseButton = _button(i)
		button.visible = index < titles.size()
		if not button.visible:
			continue
		var prefix: String = "%%PlayerTitlePickerScrollFrameButton%d" % (i + 1)
		(get_node(prefix + "TitleText") as Label).text = titles[index]["name"]
		var bit: int = titles[index]["bit"]
		var checked: bool = bit == chosen or (bit == NO_TITLE and chosen == 0)
		(get_node(prefix + "Check") as CanvasItem).visible = checked


func _button(index: int) -> BaseButton:
	return get_node("%%PlayerTitlePickerScrollFrameButton%d" % (index + 1))


func _on_button_pressed(index: int) -> void:
	var title: Dictionary = titles[_offset + index]
	WowClient.achievements.set_title(title["bit"])
	hide()
	title_chosen.emit(title["name"])


func _on_scrolled(value: float) -> void:
	_offset = roundi(value)
	_update()
