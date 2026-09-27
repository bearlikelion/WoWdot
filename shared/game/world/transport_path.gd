class_name TransportPath
extends RefCounted

# TaxiPathNode flags: 1 teleports to the next node, and 2 stops for the node's delay.
const FLAG_TELEPORT: int = 1
const FLAG_STOP: int = 2
const STEPS_PER_SEGMENT: int = 3
const DIRECTION_STEP: float = 0.01
const SYNC_COARSE_MSEC: int = 250
const SYNC_FINE_MSEC: int = 10
# Yards a matching position may be traded for heading or for a smaller shift, when docked.
const SYNC_HEADING_YARDS: float = 50.0
const SYNC_SHIFT_YARDS_PER_SECOND: float = 0.1

## The path's whole loop in milliseconds, as the server's pathTime.
var period: int = 0

var _frames: Array[Dictionary] = []
var _speed: float = 0.0
var _accel: float = 0.0
var _accel_time: float = 0.0
var _accel_dist: float = 0.0
var _last_stop: int = 0


# TransportMgr::GeneratePath: Catmull-Rom legs between map changes, eased in and out of each stop.
static func build(route: Dictionary, speed: float, accel: float) -> TransportPath:
	var points: PackedVector3Array = route["points"]
	var maps: PackedInt32Array = route["maps"]
	var flags: PackedInt32Array = route["flags"]
	var delays: PackedInt32Array = route["delays"]
	if points.size() < 4 or speed <= 0.0 or accel <= 0.0:
		return null
	var path: TransportPath = TransportPath.new()
	path._speed = speed
	path._accel = accel
	path._accel_time = speed / accel
	path._accel_dist = 0.5 * speed * speed / accel
	var frames: Array[Dictionary] = path._frames
	var controls: PackedVector3Array = []
	var map_change: bool = false
	for i: int in points.size():
		if map_change:
			map_change = false
			continue
		if i != points.size() - 1 and (flags[i] & FLAG_TELEPORT or maps[i] != maps[i + 1]):
			if not frames.is_empty():
				frames.back()["teleport"] = true
			map_change = true
			continue
		frames.append({
			"point": points[i], "map": maps[i], "stop": flags[i] == FLAG_STOP,
			"delay": delays[i], "teleport": false, "next_dist": 0.0, "time_to": 0.0,
		})
		controls.append(points[i])
	# The first and last nodes only shape the spline's ends.
	frames.pop_front()
	frames.pop_back()
	controls.remove_at(0)
	controls.remove_at(controls.size() - 1)
	if frames.size() < 2:
		return null
	frames.back()["teleport"] = true
	path._measure(controls)
	path._time()
	return path


# The server's single-float timetable drifts from ours by ms a lap; match its create block instead.
func sync_shift(msec: int, at: Vector3, orientation: float) -> int:
	var best: int = 0
	var best_score: float = INF
	for shift: int in range(0, period, SYNC_COARSE_MSEC):
		var score: float = _mismatch(msec, shift, at, orientation)
		if score < best_score:
			best_score = score
			best = shift
	var coarse: int = best
	for shift: int in range(coarse - SYNC_COARSE_MSEC, coarse + SYNC_COARSE_MSEC, SYNC_FINE_MSEC):
		var score: float = _mismatch(msec, shift, at, orientation)
		if score < best_score:
			best_score = score
			best = shift
	# The shortest way round the loop, so a shift behind the server reads as negative.
	return posmod(best + period / 2, period) - period / 2


func _mismatch(msec: int, shift: int, at: Vector3, orientation: float) -> float:
	var place: Dictionary = locate(msec + shift)
	var score: float = (place["at"] as Vector3).distance_to(at)
	var toward: Vector3 = place["toward"]
	if toward != Vector3.ZERO:
		var turn: float = angle_difference(heading(toward), orientation)
		score += SYNC_HEADING_YARDS * (1.0 - cos(turn))
	var nearest: int = mini(posmod(shift, period), period - posmod(shift, period))
	return score + nearest / 1000.0 * SYNC_SHIFT_YARDS_PER_SECOND


## The Y rotation of a transport moving along toward; MotionTransport faces it pi from its travel.
static func heading(toward: Vector3) -> float:
	return atan2(-toward.x, -toward.z) + PI


# Where the transport stands at a point in its loop: {"at", "toward", "map"}.
func locate(msec: int) -> Dictionary:
	var timer: int = posmod(msec, maxi(period, 1))
	for frame: Dictionary in _frames:
		if timer >= frame["arrive"] and timer < frame["depart"]:
			return {"at": frame["point"], "toward": Vector3.ZERO, "map": frame["map"]}
		if timer < frame["depart"] or timer >= frame["next_arrive"]:
			continue
		if frame["next_dist"] <= 0.0:
			break
		var t: float = _segment_pos(frame, timer / 1000.0)
		var spline: PackedVector3Array = frame["spline"]
		var index: int = frame["index"]
		var toward: Vector3 = _evaluate(spline, index, minf(t + DIRECTION_STEP, 1.0)) \
				- _evaluate(spline, index, maxf(t - DIRECTION_STEP, 0.0))
		return {"at": _evaluate(spline, index, t), "toward": toward, "map": frame["map"]}
	var last: Dictionary = _frames.back()
	return {"at": last["point"], "toward": Vector3.ZERO, "map": last["map"]}


# Each run between teleports is its own spline; a frame knows its leg's length to the next.
func _measure(controls: PackedVector3Array) -> void:
	var first_stop: int = -1
	_last_stop = -1
	_frames[0]["dist_from_prev"] = 0.0
	_frames[0]["index"] = 1
	if _frames[0]["stop"]:
		first_stop = 0
		_last_stop = 0
	var start: int = 0
	for i: int in range(1, _frames.size()):
		if _frames[i - 1]["teleport"] or i + 1 == _frames.size():
			var extra: int = 0 if _frames[i - 1]["teleport"] else 1
			var spline: PackedVector3Array = _spline(controls.slice(start, i + extra))
			var lengths: PackedFloat32Array = _lengths(spline)
			for j: int in range(start, i + extra):
				var k: int = j - start
				_frames[j]["index"] = k + 1
				_frames[j]["dist_from_prev"] = lengths[k + 1] - lengths[k]
				if j > 0:
					_frames[j - 1]["next_dist"] = _frames[j]["dist_from_prev"]
				_frames[j]["spline"] = spline
			if _frames[i - 1]["teleport"]:
				_frames[i]["index"] = i - start + 1
				_frames[i]["dist_from_prev"] = 0.0
				_frames[i - 1]["next_dist"] = 0.0
				_frames[i]["spline"] = spline
			start = i
		if _frames[i]["stop"]:
			if first_stop == -1:
				first_stop = i
			_last_stop = i
	_frames.back()["next_dist"] = _frames[0]["dist_from_prev"]
	if first_stop == -1:
		first_stop = 0
		_last_stop = 0
	var count: int = _frames.size()
	var walked: float = 0.0
	for i: int in count:
		var j: int = (i + _last_stop) % count
		if _frames[j]["stop"] or j == _last_stop:
			walked = 0.0
		else:
			walked += _frames[j]["dist_from_prev"]
		_frames[j]["since_stop"] = walked
	walked = 0.0
	for i: int in range(count - 1, -1, -1):
		var j: int = (i + first_stop) % count
		walked += _frames[(j + 1) % count]["dist_from_prev"]
		_frames[j]["until_stop"] = walked
		if _frames[j]["stop"] or j == first_stop:
			walked = 0.0


# The seconds from each frame to the next stop and back to the last, then the loop's timetable.
func _time() -> void:
	for frame: Dictionary in _frames:
		var since: float = frame["since_stop"]
		var until: float = frame["until_stop"]
		if since + until < 2.0 * _accel_dist:
			if since < until:
				frame["time_to"] = 2.0 * sqrt((until + since) / _accel) - sqrt(2.0 * since / _accel)
			else:
				frame["time_to"] = sqrt(2.0 * until / _accel)
		elif since < _accel_dist:
			var segment: float = (until + since) / _speed + _speed / _accel
			frame["time_to"] = segment - sqrt(2.0 * since / _accel)
		elif until < _accel_dist:
			frame["time_to"] = sqrt(2.0 * until / _accel)
		else:
			frame["time_to"] = until / _speed + 0.5 * _speed / _accel
	var count: int = _frames.size()
	var segment_time: float = 0.0
	for i: int in count:
		var j: int = (i + _last_stop) % count
		if _frames[j]["stop"] or j == _last_stop:
			segment_time = _frames[j]["time_to"]
		_frames[j]["time_from"] = segment_time - _frames[j]["time_to"]
	_frames[0]["arrive"] = 0
	var now: float = 0.0
	if _frames[0]["stop"]:
		now = _frames[0]["delay"]
	_frames[0]["depart"] = int(now * 1000.0)
	for i: int in range(1, count):
		now += _frames[i - 1]["time_to"]
		if _frames[i]["stop"]:
			_frames[i]["arrive"] = int(now * 1000.0)
			now += _frames[i]["delay"]
		else:
			now -= _frames[i]["time_to"]
			_frames[i]["arrive"] = int(now * 1000.0)
		_frames[i - 1]["next_arrive"] = _frames[i]["arrive"]
		_frames[i]["depart"] = int(now * 1000.0)
	_frames.back()["next_arrive"] = _frames.back()["depart"]
	period = _frames.back()["depart"]


# MotionTransport::CalculateSegmentPos: how far into its leg a frame is, eased from the nearer stop.
func _segment_pos(frame: Dictionary, now: float) -> float:
	var since: float = frame["time_from"] + now - frame["depart"] / 1000.0
	var until: float = frame["time_to"] - (now - frame["depart"] / 1000.0)
	var position: float = 0.0
	if since < until:
		position = _eased(since) - frame["since_stop"]
	else:
		position = frame["until_stop"] - _eased(until)
	return position / frame["next_dist"]


func _eased(seconds: float) -> float:
	if seconds < _accel_time:
		return 0.5 * _accel * seconds * seconds
	return _accel_dist + (seconds - _accel_time) * _speed


# SplineBase::InitCatmullRom: a virtual point one yard behind the start along the world's x axis.
static func _spline(controls: PackedVector3Array) -> PackedVector3Array:
	var spline: PackedVector3Array = [controls[0] - WowCoords.to_godot(Vector3.RIGHT)]
	spline.append_array(controls)
	spline.append(controls[controls.size() - 1])
	return spline


static func _lengths(spline: PackedVector3Array) -> PackedFloat32Array:
	var lengths: PackedFloat32Array = [0.0, 0.0]
	for index: int in range(1, spline.size() - 2):
		var length: float = 0.0
		var from: Vector3 = spline[index]
		for step: int in range(1, STEPS_PER_SEGMENT + 1):
			var to: Vector3 = _evaluate(spline, index, float(step) / STEPS_PER_SEGMENT)
			length += from.distance_to(to)
			from = to
		lengths.append(lengths[index] + length)
	return lengths


static func _evaluate(spline: PackedVector3Array, index: int, t: float) -> Vector3:
	return spline[index].cubic_interpolate(
		spline[index + 1], spline[index - 1], spline[index + 2], t
	)
