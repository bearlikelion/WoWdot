@tool
class_name WowButton
extends TextureButton

# The FrameXML state textures are child TextureRects named after the state they draw.
const STATES: PackedStringArray = [
	"NormalTexture", "PushedTexture", "DisabledTexture", "CheckedTexture",
	"DisabledCheckedTexture", "HighlightTexture",
]

# WoW's SetChecked: separate from Godot's toggle state so clicks never flip it.
@export var checked: bool = false:
	set(value):
		checked = value
		queue_redraw()
# WoW's LockHighlight: the highlight stays on without the mouse over the button.
@export var highlight_locked: bool = false:
	set(value):
		highlight_locked = value
		queue_redraw()

var _states: Dictionary[String, CanvasItem] = {}


func _ready() -> void:
	for state: String in STATES:
		var node: CanvasItem = get_node_or_null(state)
		if node:
			_states[state] = node
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var mode: DrawMode = get_draw_mode()
	var pushed: bool = mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
	var hovered: bool = is_hovered() and not disabled
	_show("DisabledTexture", disabled)
	_show("PushedTexture", pushed and not disabled)
	var normal_hidden: bool = (pushed and _states.has("PushedTexture")) \
	or (disabled and _states.has("DisabledTexture"))
	_show("NormalTexture", not normal_hidden)
	_show("CheckedTexture", checked and not disabled)
	_show("DisabledCheckedTexture", checked and disabled)
	_show("HighlightTexture", hovered or highlight_locked)


func _show(state: String, shown: bool) -> void:
	if _states.has(state):
		_states[state].visible = shown
