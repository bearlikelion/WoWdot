class_name BuffFrame
extends Control

const HELPFUL_BUTTONS: int = 16
const HARMFUL_BUTTONS: int = 8
# BUFF_WARNING_TIME: auras this close to running out pulse between full and BUFF_MIN_ALPHA.
const WARNING_MSEC: int = 31000
const FLASH_SECONDS: float = 0.75
const MIN_ALPHA: float = 0.3

var _buttons: Array[WowButton] = []
var _icons: Array[TextureRect] = []
var _counts: Array[Label] = []
var _durations: Array[Label] = []
var _borders: Array[TextureRect] = []
var _shown: Array[Dictionary] = []
# Aura slot to the tick (msec) it runs out; only the player's own auras get durations.
var _ends: Dictionary[int, int] = {}


func _ready() -> void:
	for i: int in HELPFUL_BUTTONS + HARMFUL_BUTTONS:
		var button: WowButton = get_node("%%BuffButton%d" % i)
		button.button_mask = MOUSE_BUTTON_MASK_RIGHT
		button.pressed.connect(_on_button_pressed.bind(i))
		button.mouse_entered.connect(_on_button_hovered.bind(i))
		button.mouse_exited.connect(_on_button_left.bind(i))
		_buttons.append(button)
		_icons.append(get_node("%%BuffButton%dIcon" % i))
		_counts.append(get_node("%%BuffButton%dCount" % i))
		_durations.append(get_node("%%BuffButton%dDuration" % i))
		_borders.append(get_node_or_null("%%BuffButton%dBorder" % i))
	var session: WowSession = WowClient.session
	session.object_updated.connect(_on_object_updated)
	session.aura_duration.connect(_on_aura_duration)
	refresh()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	var pulse: float = absf(fmod(now / 1000.0, FLASH_SECONDS * 2.0) - FLASH_SECONDS) / FLASH_SECONDS
	for i: int in _shown.size():
		if _shown[i].is_empty():
			continue
		var end: int = _ends.get(_shown[i]["slot"], 0)
		var left: int = end - now
		_durations[i].visible = end > 0 and left > 0
		if _durations[i].visible:
			_durations[i].text = _duration_text(left)
		_buttons[i].modulate.a = lerpf(MIN_ALPHA, 1.0, pulse) if end > 0 and left < WARNING_MSEC else 1.0


func refresh() -> void:
	var session: WowSession = WowClient.session
	var auras: Array[Dictionary] = UnitAuras.read(session, session.get_player_guid())
	var helpful: Array[Dictionary] = []
	var harmful: Array[Dictionary] = []
	for aura: Dictionary in auras:
		(harmful if aura["harmful"] else helpful).append(aura)
	_shown.clear()
	for i: int in HELPFUL_BUTTONS + HARMFUL_BUTTONS:
		var source: Array[Dictionary] = helpful if i < HELPFUL_BUTTONS else harmful
		var index: int = i if i < HELPFUL_BUTTONS else i - HELPFUL_BUTTONS
		var aura: Dictionary = source[index] if index < source.size() else {}
		_shown.append(aura)
		_buttons[i].visible = not aura.is_empty()
		if aura.is_empty():
			continue
		_icons[i].texture = WowAssets.spells.icon(aura["spell"])
		_counts[i].visible = aura["stacks"] > 1
		_counts[i].text = str(aura["stacks"])
		if _borders[i]:
			_borders[i].self_modulate = UnitAuras.border_color(aura["spell"])


# BuffFrame_UpdateDuration: minutes above a minute, seconds below.
func _duration_text(left_msec: int) -> String:
	var seconds: int = ceili(left_msec / 1000.0)
	return "%d m" % ceili(seconds / 60.0) if seconds > 60 else "%d s" % seconds


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid():
		refresh()


func _on_aura_duration(slot: int, duration_msec: int) -> void:
	_ends[slot] = Time.get_ticks_msec() + duration_msec if duration_msec > 0 else 0


# BuffButton_OnEnter anchors the tooltip below and left of the button.
func _on_button_hovered(index: int) -> void:
	var aura: Dictionary = _shown[index] if index < _shown.size() else {}
	if not aura.is_empty() and GameTooltip.current:
		var anchor: GameTooltip.TooltipAnchor = GameTooltip.TooltipAnchor.BOTTOM_LEFT
		GameTooltip.current.set_aura(_buttons[index], aura["spell"], anchor)


func _on_button_left(index: int) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(_buttons[index])


# Right-clicking a buff cancels it; debuffs cannot be removed that way.
func _on_button_pressed(index: int) -> void:
	var aura: Dictionary = _shown[index] if index < _shown.size() else {}
	if not aura.is_empty() and not aura["harmful"]:
		WowClient.session.cancel_aura(aura["spell"])
