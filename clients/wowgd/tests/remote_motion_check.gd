class_name RemoteMotionCheck
extends Node3D

const STEP: float = 1.0 / 60.0

var _failures: PackedStringArray = []


# Feeds RemoteMotion relayed packets and checks where it carries the player between them.
func _ready() -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var speeds: Dictionary = {
		"walk_speed": 2.5, "run_speed": 7.0, "run_back_speed": 4.5, "swim_speed": 4.7,
		"swim_back_speed": 2.5, "turn_rate": PI,
	}
	var run: RemoteMotion = _motion(Player.MoveFlag.FORWARD, 0.0, speeds)
	_check(_near(_run_for(run, 1.0, space), Vector3(7.0, 0.0, 0.0)), "runs 7 yards north a second")
	var strafe: RemoteMotion = _motion(Player.MoveFlag.STRAFE_LEFT, 0.0, speeds)
	_check(_near(_run_for(strafe, 1.0, space), Vector3(0.0, 7.0, 0.0)), "strafes left toward +Y")
	var mounted: Dictionary = speeds.duplicate()
	mounted["run_speed"] = 14.0
	var fast: RemoteMotion = _motion(Player.MoveFlag.FORWARD, PI / 2.0, mounted)
	_check(_near(_run_for(fast, 1.0, space), Vector3(0.0, 14.0, 0.0)), "rides at the relayed speed")
	var turn: RemoteMotion = _motion(Player.MoveFlag.TURN_LEFT, 0.0, speeds)
	_run_for(turn, 0.5, space)
	_check(is_equal_approx(turn.orientation, PI / 2.0), "turns left at the turn rate")
	var jump: Dictionary = speeds.duplicate()
	jump["jump_velocity"] = Vector3(0.0, 0.0, Player.JUMP_VELOCITY)
	var hop: RemoteMotion = _motion(Player.MoveFlag.JUMPING, 0.0, jump)
	var peak: float = 0.0
	for i: int in 30:
		peak = maxf(peak, WowCoords.from_godot(hop.advance(STEP, space)).z)
	_check(peak > 1.0 and peak < 2.0, "jumps about as high as the local player")
	var teleport: RemoteMotion = RemoteMotion.new()
	var far: Vector3 = Vector3(100.0, 0.0, 0.0)
	teleport.update(_packet(Player.MoveFlag.NONE, 0.0, speeds, far), Vector3.ZERO)
	var drawn: Vector3 = WowCoords.from_godot(teleport.advance(STEP, space))
	_check(_near(drawn, far), "snaps across a teleport")
	var drift: RemoteMotion = RemoteMotion.new()
	drift.update(_packet(Player.MoveFlag.NONE, 0.0, speeds, Vector3(2.0, 0.0, 0.0)), Vector3.ZERO)
	var eased: Vector3 = WowCoords.from_godot(drift.advance(STEP, space))
	_check(eased.x > 0.0 and eased.x < 2.0, "eases a small correction in")
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("remote_motion_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _motion(flags: int, orientation: float, extra: Dictionary) -> RemoteMotion:
	var motion: RemoteMotion = RemoteMotion.new()
	motion.update(_packet(flags, orientation, extra, Vector3.ZERO), Vector3.ZERO)
	return motion


func _packet(flags: int, orientation: float, extra: Dictionary, at: Vector3) -> Dictionary:
	var packet: Dictionary = extra.duplicate()
	packet["flags"] = flags
	packet["orientation"] = orientation
	packet["position"] = at
	return packet


# Advances for the given time and returns the WoW-space position reached.
func _run_for(motion: RemoteMotion, seconds: float, space: PhysicsDirectSpaceState3D) -> Vector3:
	var at: Vector3 = Vector3.ZERO
	for i: int in roundi(seconds / STEP):
		at = motion.advance(STEP, space)
	return WowCoords.from_godot(at)


func _near(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < 0.05


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)
