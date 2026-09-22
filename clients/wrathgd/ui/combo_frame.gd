class_name ComboFrame
extends Control

const MAX_COMBO_POINTS: int = 5

var target: int = 0:
	set(value):
		target = value
		_refresh()

var _combo_target: int = 0
var _points: int = 0


func _ready() -> void:
	WowClient.session.packet_received.connect(_on_packet_received)
	modulate.a = 1.0
	_refresh()


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_UPDATE_COMBO_POINTS":
		return
	var reader: PacketReader = PacketReader.new(payload)
	_combo_target = reader.packed_guid()
	_points = reader.u8()
	_refresh()


# ComboFrame_Update: the points only show while their target is the one selected.
func _refresh() -> void:
	var shown: int = _points if target != 0 and target == _combo_target else 0
	visible = shown > 0
	for i: int in MAX_COMBO_POINTS:
		(get_node("%%ComboPoint%dHighlight" % (i + 1)) as CanvasItem).visible = i < shown
		var shine: CanvasItem = get_node_or_null("%%ComboPoint%dShine" % (i + 1))
		if shine:
			shine.hide()
