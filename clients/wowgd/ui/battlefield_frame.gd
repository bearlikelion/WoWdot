class_name BattlefieldFrame
extends Control

signal close_requested
signal open_requested

const ZONES_DISPLAYED: int = 12
const ZONE_HEIGHT: float = 16.0

var _map_id: int = 0
# Row 0 is "First Available", which the wire spells as instance 0.
var _instances: PackedInt32Array = []
var _selected: int = 0
var _offset: int = 0

@onready var _scroll: WowScrollFrame = %BattlefieldListScrollFrame


func _ready() -> void:
	for i: int in ZONES_DISPLAYED:
		_row(i).pressed.connect(_on_row_pressed.bind(i))
	_scroll.faux = true
	_scroll.scrolled.connect(_on_scrolled)
	%BattlefieldFrameJoinButton.pressed.connect(_join.bind(false))
	%BattlefieldFrameGroupJoinButton.pressed.connect(_join.bind(true))
	%BattlefieldFrameCancelButton.pressed.connect(close_requested.emit)
	%BattlefieldFrameCloseButton.pressed.connect(close_requested.emit)
	(%BattlefieldFrameZoneDescription as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	WowClient.battlegrounds.listed.connect(_on_listed)


func set_portrait(texture: Texture2D) -> void:
	(%BattlefieldFramePortrait as TextureRect).texture = texture


func refresh() -> void:
	var title: String = WowClient.map_display_name(_map_id)
	%BattlefieldFrameFrameLabel.text = title
	%BattlefieldFrameNameHeader.text = WowStrings.get_text("BATTLEFIELD_NAME")
	%BattlefieldFrameZoneDescription.text = WowStrings.get_text(
		"FIRST_AVAILABLE_TOOLTIP" if _selected == 0 else "BATTLEGROUND_INSTANCE_TOOLTIP"
	)
	_scroll.set_range(maxi(_instances.size() - ZONES_DISPLAYED, 0))
	for i: int in ZONES_DISPLAYED:
		var row: WowButton = _row(i)
		var index: int = i + _offset
		row.visible = index < _instances.size()
		if not row.visible:
			continue
		var text: Label = get_node("%%BattlefieldZone%dText" % (i + 1))
		text.text = WowStrings.get_text("FIRST_AVAILABLE") if index == 0 \
		else "%s %d" % [title, _instances[index]]
		(get_node("%%BattlefieldZone%dStatus" % (i + 1)) as Label).text = ""
		row.highlight_locked = index == _selected
	var leads: bool = PartyFrame.in_party() \
	and PartyFrame.leader == WowClient.session.get_player_guid()
	(%BattlefieldFrameGroupJoinButton as BaseButton).disabled = not leads


func _row(index: int) -> WowButton:
	return get_node("%%BattlefieldZone%d" % (index + 1))


func _join(as_group: bool) -> void:
	var battlegrounds: Battlegrounds = WowClient.battlegrounds
	battlegrounds.join(battlegrounds.battlemaster, _map_id, _instances[_selected], as_group)
	close_requested.emit()


func _on_listed(map_id: int, instances: PackedInt32Array) -> void:
	_map_id = map_id
	_instances = PackedInt32Array([0])
	_instances.append_array(instances)
	_selected = 0
	_offset = 0
	open_requested.emit()
	refresh()


func _on_row_pressed(index: int) -> void:
	_selected = index + _offset
	refresh()


func _on_scrolled(value: float) -> void:
	var offset: int = roundi(value)
	if offset != _offset:
		_offset = offset
		refresh()
