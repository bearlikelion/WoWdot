class_name TransportCheck
extends Node

# The Thundercaller, Iron Eagle, Lady Mehley and Mighty Wind: taxi path, speed and acceleration.
const TRANSPORTS: Array[Array] = [[302, 30, 1], [285, 30, 1], [292, 30, 1], [712, 30, 1]]
const STEP_MSEC: int = 100
# 30 yards a second covers 3 in a step; the spline's uneven parameter speed adds a little.
const MAX_STEP_YARDS: float = 6.0

var _failures: PackedStringArray = []


func _ready() -> void:
	for spec: Array in TRANSPORTS:
		_check_path(spec[0], spec[1], spec[2])
	print("transport_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_path(path_id: int, speed: float, accel: float) -> void:
	var path: TransportPath = TransportPath.build(TaxiNodes.path_route(path_id), speed, accel)
	if path == null:
		_failures.append("path %d builds" % path_id)
		return
	var stopped: int = 0
	var largest: float = 0.0
	var previous: Dictionary = path.locate(0)
	for msec: int in range(STEP_MSEC, path.period, STEP_MSEC):
		var place: Dictionary = path.locate(msec)
		if place["toward"] == Vector3.ZERO:
			stopped += STEP_MSEC
		if place["map"] == previous["map"]:
			largest = maxf(largest, (place["at"] as Vector3).distance_to(previous["at"]))
		previous = place
	print("path %d: %.1f s loop, %.1f s docked, largest step %.2f yd" % [
		path_id, path.period / 1000.0, stopped / 1000.0, largest,
	])
	if stopped == 0:
		_failures.append("path %d docks" % path_id)
	if largest > MAX_STEP_YARDS:
		_failures.append("path %d moves without jumps" % path_id)
