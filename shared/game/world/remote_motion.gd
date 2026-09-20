class_name RemoteMotion
extends RefCounted

# A new packet's position eases in over about this long instead of popping.
const CORRECTION_SECONDS: float = 0.1
# Farther than this from where the model is drawn is a teleport, not drift.
const SNAP_DISTANCE: float = 20.0
const GROUND_PROBE: float = 3.0
const AIRBORNE: int = Player.MoveFlag.JUMPING | Player.MoveFlag.FALLING_FAR
const TRAVEL: int = Player.LONGITUDINAL | Player.STRAFE

var flags: int = Player.MoveFlag.NONE
var orientation: float = 0.0

# WoW-space position carried forward from the last relayed MovementInfo.
var _position: Vector3 = Vector3.ZERO
var _offset: Vector3 = Vector3.ZERO
var _movement: Dictionary = {}
var _velocity: Vector3 = Vector3.ZERO


# Takes a relayed movement; drawn_at is where the model is now, so the step to the new spot eases.
func update(movement: Dictionary, drawn_at: Vector3) -> void:
	_movement = movement
	flags = movement.get("flags", Player.MoveFlag.NONE)
	orientation = movement.get("orientation", orientation)
	_position = movement["position"]
	# The packet carries the take-off velocity and how long the unit has been in the air since.
	_velocity = movement.get("jump_velocity", Vector3.ZERO)
	_velocity.z -= Player.GRAVITY * int(movement.get("fall_time_msec", 0)) / 1000.0
	_offset = drawn_at - WowCoords.to_godot(_position)
	if _offset.length() > SNAP_DISTANCE:
		_offset = Vector3.ZERO


# Moves the reckoning on by delta and returns where to draw the model.
func advance(delta: float, space: PhysicsDirectSpaceState3D) -> Vector3:
	if flags & Player.MoveFlag.TURN_LEFT:
		orientation += _speed("turn_rate") * delta
	elif flags & Player.MoveFlag.TURN_RIGHT:
		orientation -= _speed("turn_rate") * delta
	if flags & AIRBORNE:
		_velocity.z -= Player.GRAVITY * delta
		_position += _velocity * delta
		var ground: float = _ground(space)
		if _velocity.z < 0.0 and _position.z < ground:
			_position.z = ground
	elif flags & TRAVEL and not flags & Player.MoveFlag.ROOT:
		_position += _planar_velocity() * delta
		var ground: float = _ground(space)
		if not flags & Player.MoveFlag.SWIMMING and not is_nan(ground):
			_position.z = ground
	_offset = _offset.lerp(Vector3.ZERO, minf(delta / CORRECTION_SECONDS, 1.0))
	return WowCoords.to_godot(_position) + _offset


func _planar_velocity() -> Vector3:
	var forward: Vector2 = Vector2.from_angle(orientation)
	var direction: Vector2 = Vector2.ZERO
	if flags & Player.MoveFlag.FORWARD:
		direction += forward
	elif flags & Player.MoveFlag.BACKWARD:
		direction -= forward
	# WoW's +Y is to the left of +X, so the left strafe is the counter-clockwise normal.
	if flags & Player.MoveFlag.STRAFE_LEFT:
		direction -= forward.orthogonal()
	elif flags & Player.MoveFlag.STRAFE_RIGHT:
		direction += forward.orthogonal()
	var speed_key: String = "run_speed"
	if flags & Player.MoveFlag.SWIMMING:
		speed_key = "swim_back_speed" if flags & Player.MoveFlag.BACKWARD else "swim_speed"
	elif flags & Player.MoveFlag.BACKWARD:
		speed_key = "run_back_speed"
	elif flags & Player.MoveFlag.WALK_MODE:
		speed_key = "walk_speed"
	var planar: Vector2 = direction.normalized() * _speed(speed_key)
	return Vector3(planar.x, planar.y, 0.0)


func _speed(key: String) -> float:
	return _movement.get(key, 0.0)


# The ground height under the reckoned position, or NAN where nothing solid has loaded.
func _ground(space: PhysicsDirectSpaceState3D) -> float:
	var at: Vector3 = WowCoords.to_godot(_position)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		at + Vector3.UP * GROUND_PROBE, at + Vector3.DOWN * GROUND_PROBE
	)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty() or hit["collider"] is CharacterBody3D:
		return NAN
	return WowCoords.from_godot(hit["position"]).z
