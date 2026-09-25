class_name WorldStateHeader
extends VBoxContainer

const ROW: PackedScene = preload("res://ui/world_state_row.tscn")
# WorldStateUI.dbc: where the line shows, its art and text, the state that gates it, and its kind.
const MAP_COLUMN: int = 1
const ZONE_COLUMN: int = 2
const ICON_COLUMN: int = 3
const TEXT_COLUMN: int = 4
const GATE_COLUMN: int = 23
const KIND_COLUMN: int = 24
# Kind 1 lines sit at the top of the screen; kind 2 are the scoreboard's columns.
const ALWAYS_UP: int = 1

var _table: WowDBC
var _map_id: int = -1
var _zone_id: int = 0
var _token: RegEx = RegEx.new()


func _ready() -> void:
	_table = WowDBC.open(WowAssets.archive, "WorldStateUI")
	# The text names a world state as %2327w, which stands for that state's value.
	_token.compile("%(\\d+)w")
	WowClient.battlegrounds.world_state_changed.connect(_on_world_state_changed)


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
	if _table == null:
		return
	var battlegrounds: Battlegrounds = WowClient.battlegrounds
	for row: int in _table.row_count():
		if _table.get_uint(row, KIND_COLUMN) != ALWAYS_UP \
		or _table.get_uint(row, MAP_COLUMN) != _map_id:
			continue
		var zone: int = _table.get_uint(row, ZONE_COLUMN)
		if zone != 0 and zone != _zone_id:
			continue
		var gate: int = _table.get_uint(row, GATE_COLUMN)
		if gate != 0 and battlegrounds.world_state(gate) == 0:
			continue
		var text: String = _table.get_text(row, TEXT_COLUMN)
		for found: RegExMatch in _token.search_all(text):
			var value: int = battlegrounds.world_state(found.get_string(1).to_int())
			text = text.replace(found.get_string(0), str(value))
		var line: Control = ROW.instantiate()
		add_child(line)
		(line.get_node("%Text") as Label).text = text
		var icon: String = _table.get_string(row, ICON_COLUMN)
		var art: TextureRect = line.get_node("%Icon")
		art.visible = not icon.is_empty()
		if not icon.is_empty():
			var texture: WowTexture = WowTexture.new()
			texture.file = icon + ".blp"
			art.texture = texture


func _on_world_state_changed(_field: int, _value: int) -> void:
	refresh.call_deferred()
