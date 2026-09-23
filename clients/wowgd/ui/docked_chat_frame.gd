@tool
class_name DockedChatFrame
extends WowScrollingMessageFrame

signal tab_selected
signal tab_menu_requested

# DEFAULT_CHATFRAME_COLOR, _ALPHA and CHAT_FRAME_FADE_TIME from FloatingChatFrame.lua.
const DEFAULT_BACKGROUND: Color = Color(0.0, 0.0, 0.0, 0.25)
const FADE_TIME: float = 0.15
# FCF_DockUpdate: unselected docked tabs show at half alpha, resized with 5 padding.
const UNSELECTED_TAB_ALPHA: float = 0.5
const TAB_PADDING: float = 5.0
const UNUSED: Array[String] = [
	"ResizeTopLeft", "ResizeTopRight", "ResizeBottomLeft", "ResizeBottomRight", "ResizeTop",
	"ResizeBottom", "ResizeLeft", "ResizeRight", "TabDropDown", "TabFlash",
]
const SCROLL_BUTTONS: Array[String] = ["UpButton", "DownButton", "BottomButton"]

## The node names' prefix when it is not the frame's own name, as for an extra chat window.
@export var stem: String = ""

var selected: bool = true
## ChatTypeGroup names this window shows, such as SAY or LOOT.
var message_groups: PackedStringArray = []
## The channels it shows; "*" stands for every channel.
var channels: PackedStringArray = []
## FCF_SetWindowColor and FCF_SetWindowAlpha: the backdrop shown while the cursor is over it.
var background_color: Color = DEFAULT_BACKGROUND:
	set(value):
		background_color = value
		if is_node_ready():
			_fade_to(_hovered)
## FCF_SetWindowName: the tab's text; the HUD lines the tabs up again after a change.
var window_name: String = "":
	set(value):
		window_name = value
		if is_node_ready():
			(get_node("%" + _stem() + "TabText") as Label).text = value

var _hovered: bool = false
var _fade: Tween

@onready var _tab: TextureButton = get_node("%" + _stem() + "Tab")
@onready var _background: TextureRect = get_node("%" + _stem() + "Background")


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	for unused: String in UNUSED:
		var node: CanvasItem = get_node_or_null("%" + _stem() + unused)
		if node:
			node.hide()
	_background.self_modulate = Color(0.0, 0.0, 0.0, 0.0)
	_tab.modulate.a = 0.0
	_tab.hide()
	_tab.pressed.connect(tab_selected.emit)
	_tab.gui_input.connect(_on_tab_input)
	window_name = (get_node("%" + _stem() + "TabText") as Label).text
	(get_node("%" + _stem() + "UpButton") as BaseButton).pressed.connect(scroll_up)
	(get_node("%" + _stem() + "DownButton") as BaseButton).pressed.connect(scroll_down)
	(get_node("%" + _stem() + "BottomButton") as BaseButton).pressed.connect(scroll_to_bottom)


# MouseIsOver(chatFrame, 45, -10, -5, 5): the area reaches up over the tabs.
func is_hovered() -> bool:
	var area: Rect2 = Rect2(Vector2.ZERO, size).grow_individual(5.0, 45.0, 5.0, 10.0)
	return area.has_point(get_local_mouse_position())


func tab_position() -> Vector2:
	return _tab.position


# FCF_SetTabPosition: lines the tab up after the docked tabs before it; returns its width.
func dock_tab(at: Vector2) -> float:
	PanelManager.resize_tab(_tab, TAB_PADDING)
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_tab.set_anchor(side, 0.0)
	_tab.position = at
	return _tab.size.x


func set_selected(value: bool) -> void:
	selected = value
	mouse_filter = Control.MOUSE_FILTER_PASS if value else Control.MOUSE_FILTER_IGNORE
	_lines.get_parent().visible = value
	for button: String in SCROLL_BUTTONS:
		(get_node("%" + _stem() + button) as CanvasItem).visible = value
	_fade_to(_hovered)


func set_hovered(value: bool) -> void:
	if value != _hovered:
		_hovered = value
		_fade_to(value)


func _fade_to(shown: bool) -> void:
	if _fade:
		_fade.kill()
	var tab_alpha: float = (1.0 if selected else UNSELECTED_TAB_ALPHA) if shown else 0.0
	if shown:
		_tab.show()
	_fade = create_tween().set_parallel()
	_fade.tween_property(_tab, "modulate:a", tab_alpha, FADE_TIME)
	_fade.tween_property(
		_background, "self_modulate",
		background_color if shown and selected else Color(background_color, 0.0), FADE_TIME
	)
	if not shown:
		_fade.chain().tween_callback(_tab.hide)


func _stem() -> String:
	return stem if not stem.is_empty() else String(name)


# FCF_Tab_OnClick: a right click opens the window's options.
func _on_tab_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click and click.button_index == MOUSE_BUTTON_RIGHT and not click.pressed:
		tab_menu_requested.emit()
