class_name MirrorTimers
extends Control

var _timers: Array[MirrorTimer] = []


func _ready() -> void:
	for child: Node in get_children():
		_timers.append(child)
	WowClient.session.packet_received.connect(_on_packet_received)
	WowClient.session.world_entered.connect(_on_world_entered)


# SMSG_START_MIRROR_TIMER: the timer, where it stands, its length, how fast it runs and a pause.
func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	match opcode:
		"SMSG_START_MIRROR_TIMER":
			var kind: MirrorTimer.Kind = reader.u32() as MirrorTimer.Kind
			var value: int = reader.u32()
			var longest: int = reader.u32()
			var scale: int = reader.i32()
			var paused: bool = reader.u8() > 0
			var timer: MirrorTimer = _free_timer(kind)
			if timer:
				timer.start(kind, value, longest, scale, paused)
		"SMSG_PAUSE_MIRROR_TIMER":
			var kind: MirrorTimer.Kind = reader.u32() as MirrorTimer.Kind
			var paused: bool = reader.u8() > 0
			for timer: MirrorTimer in _shown(kind):
				timer.pause(paused)
		"SMSG_STOP_MIRROR_TIMER":
			var kind: MirrorTimer.Kind = reader.u32() as MirrorTimer.Kind
			for timer: MirrorTimer in _shown(kind):
				timer.hide()


# MirrorTimer_Show: the timer already running this one, or the first one going spare.
func _free_timer(kind: MirrorTimer.Kind) -> MirrorTimer:
	var running: Array[MirrorTimer] = _shown(kind)
	if not running.is_empty():
		return running[0]
	for timer: MirrorTimer in _timers:
		if not timer.visible:
			return timer
	return null


func _shown(kind: MirrorTimer.Kind) -> Array[MirrorTimer]:
	return _timers.filter(
		func(timer: MirrorTimer) -> bool: return timer.visible and timer.kind == kind
	)


func _on_world_entered(_map_id: int, _position: Vector3, _orientation: float) -> void:
	_stop_all()


func _stop_all() -> void:
	for timer: MirrorTimer in _timers:
		timer.hide()
