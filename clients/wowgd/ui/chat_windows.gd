class_name ChatWindows
extends RefCounted

## The tabs need lining up again, because a window was renamed, opened or closed.
signal layout_changed

enum MenuItem { RENAME = 1, FONT_SIZE }

# CHAT_FONT_HEIGHTS from Fonts.xml.
const FONT_SIZES: Array[int] = [12, 14, 16, 18]
const DEFAULT_FONT_SIZE: int = 14

var frames: Array[DockedChatFrame] = []

var _open_menu: Callable
var _ask_name: Callable


# open_menu takes the entries and a Callable for the chosen id; ask_name a prompt and its answer.
func _init(chat_frames: Array[DockedChatFrame], open_menu: Callable, ask_name: Callable) -> void:
	frames = chat_frames
	_open_menu = open_menu
	_ask_name = ask_name
	for frame: DockedChatFrame in frames:
		frame.tab_menu_requested.connect(show_tab_menu.bind(frame))


# FCFOptionsDropDown_Initialize, a level at a time: submenus open as menus of their own.
func show_tab_menu(frame: DockedChatFrame) -> void:
	var entries: Array[Dictionary] = [
		{"text": WowStrings.get_text("RENAME_CHAT_WINDOW"), "id": MenuItem.RENAME},
		{"text": WowStrings.get_text("DISPLAY"), "title": true},
		{"text": WowStrings.get_text("FONT_SIZE"), "id": MenuItem.FONT_SIZE},
	]
	_open_menu.call(entries, func(id: int) -> void:
		match id as MenuItem:
			MenuItem.RENAME:
				_rename(frame)
			MenuItem.FONT_SIZE:
				_show_font_menu.call_deferred(frame)
	)


func _rename(frame: DockedChatFrame) -> void:
	_ask_name.call(WowStrings.get_text("NAME_CHAT_WINDOW"), func(window_name: String) -> void:
		if not window_name.strip_edges().is_empty():
			frame.window_name = window_name.strip_edges()
			layout_changed.emit()
	)


func _show_font_menu(frame: DockedChatFrame) -> void:
	var current: int = frame.font_size if frame.font_size > 0 else DEFAULT_FONT_SIZE
	var entries: Array[Dictionary] = []
	for size: int in FONT_SIZES:
		entries.append({
			"text": WowStrings.get_text("FONT_SIZE_TEMPLATE") % size, "id": size,
			"checked": size == current,
		})
	_open_menu.call(entries, func(size: int) -> void: frame.font_size = size)
