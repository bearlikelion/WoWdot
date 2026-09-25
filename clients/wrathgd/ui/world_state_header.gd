class_name WorldStateHeader
extends VBoxContainer

const ROW: PackedScene = preload("res://ui/world_state_row.tscn")
# The 3.3.5 WorldStateUI.dbc kinds: top of screen, capture bar, scoreboard column, countdown.
enum Kind { ALWAYS_UP, CAPTURE_BAR, SCOREBOARD, TIMER }

# WorldStateUI.dbc: where the line shows, its art and text, the state that gates it, and its kind.
const MAP_COLUMN: int = 1
const ZONE_COLUMN: int = 2
const ICON_COLUMN: int = 4
const TEXT_COLUMN: int = 5
const GATE_COLUMN: int = 39
const KIND_COLUMN: int = 40

var _table: WowDBC
var _map_id: int = -1
var _zone_id: int = 0
var _token: RegEx = RegEx.new()
var _timer_token: RegEx = RegEx.new()
# Countdown lines and the text they fill in, redrawn each second.
var _timers: Dictionary[Label, String] = {}
var _since_tick: float = 0.0


func _ready() -> void:
	_table = WowDBC.open(WowAssets.archive, "WorldStateUI")
	# The text names a world state as %2327w, which stands for that state's value.
	_token.compile("%(\\d+)w")
	# A %4354k names a state holding the unix time the countdown reaches.
	_timer_token.compile("%(\\d+)k")
	WowClient.battlegrounds.world_state_changed.connect(_on_world_state_changed)


func _process(delta: float) -> void:
	_since_tick += delta
	if _since_tick < 1.0 or _timers.is_empty():
		return
	_since_tick = 0.0
	for label: Label in _timers:
		label.text = _fill(_timers[label])


func show_place(map_id: int, area_id: int) -> void:
	var zone: int = AreaInfo.zone_of(area_id)
	if map_id == _map_id and zone == _zone_id:
		return
	_map_id = map_id
	_zone_id = zone
	refresh()


# ponytail: the capture point bar (the CAPTUREPOINT extended UI) and dynamic icons are not drawn.
func refresh() -> void:
	for row: Node in get_children():
		row.queue_free()
	_timers.clear()
	if _table == null:
		return
	var battlegrounds: Battlegrounds = WowClient.battlegrounds
	for row: int in _table.row_count():
		var kind: int = _table.get_uint(row, KIND_COLUMN)
		if kind not in [Kind.ALWAYS_UP, Kind.TIMER] or _table.get_uint(row, MAP_COLUMN) != _map_id:
			continue
		var zone: int = _table.get_uint(row, ZONE_COLUMN)
		if zone != 0 and zone != _zone_id:
			continue
		var gate: int = _table.get_uint(row, GATE_COLUMN)
		if gate != 0 and battlegrounds.world_state(gate) == 0:
			continue
		var template: String = _table.get_string(row, TEXT_COLUMN)
		var line: Control = ROW.instantiate()
		add_child(line)
		var label: Label = line.get_node("%Text")
		label.text = _fill(template)
		if kind == Kind.TIMER:
			_timers[label] = template
		var icon: String = _table.get_string(row, ICON_COLUMN)
		var art: TextureRect = line.get_node("%Icon")
		art.visible = not icon.is_empty()
		if not icon.is_empty():
			var texture: WowTexture = WowTexture.new()
			texture.file = icon + ".blp"
			art.texture = texture


func _fill(template: String) -> String:
	var battlegrounds: Battlegrounds = WowClient.battlegrounds
	var text: String = template
	for found: RegExMatch in _token.search_all(template):
		var value: int = battlegrounds.world_state(found.get_string(1).to_int())
		text = text.replace(found.get_string(0), str(value))
	for found: RegExMatch in _timer_token.search_all(template):
		var until: int = battlegrounds.world_state(found.get_string(1).to_int())
		var left: int = maxi(until - battlegrounds.server_time(), 0)
		var clock: String = "%d:%02d:%02d" % [left / 3600, left / 60 % 60, left % 60] \
				if left >= 3600 else "%d:%02d" % [left / 60, left % 60]
		text = text.replace(found.get_string(0), clock)
	return text


func _on_world_state_changed(_field: int, _value: int) -> void:
	refresh.call_deferred()
