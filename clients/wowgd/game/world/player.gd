class_name Player
extends CharacterBody3D

# jump_velocity is the take-off velocity, which WoW keeps for the whole jump or fall.
signal movement_changed(
	opcode: String, godot_position: Vector3, orientation: float, flags: int,
	fall_time_msec: int, jump_velocity: Vector3,
)
# A left press and release that did not orbit the camera.
signal clicked(screen_position: Vector2)
signal interacted(screen_position: Vector2)

enum MoveFlag {
	NONE = 0,
	FORWARD = 0x1,
	BACKWARD = 0x2,
	STRAFE_LEFT = 0x4,
	STRAFE_RIGHT = 0x8,
	TURN_LEFT = 0x10,
	TURN_RIGHT = 0x20,
	WALK_MODE = 0x100,
	ROOT = 0x1000,
	JUMPING = 0x2000,
	FALLING_FAR = 0x4000,
	SWIMMING = 0x200000,
}

const RUN_SPEED: float = 7.0
const BACK_SPEED: float = 4.5
const TURN_SPEED: float = PI
const GRAVITY: float = 19.29
const JUMP_VELOCITY: float = 7.95797334
const HEARTBEAT_SECONDS: float = 0.5
const FACING_SECONDS: float = 0.2
const MOUSE_TURN: float = 0.006
const START_PITCH: float = -0.3
const MIN_PITCH: float = -1.3
const MAX_PITCH: float = 0.6
const MIN_ZOOM: float = 1.5
const MAX_ZOOM: float = 30.0
const ZOOM_STEP: float = 1.2
const CLICK_SLOP: float = 4.0
const LONGITUDINAL: int = MoveFlag.FORWARD | MoveFlag.BACKWARD
const STRAFE: int = MoveFlag.STRAFE_LEFT | MoveFlag.STRAFE_RIGHT
const TURN: int = MoveFlag.TURN_LEFT | MoveFlag.TURN_RIGHT
const AIRBORNE: int = MoveFlag.JUMPING | MoveFlag.FALLING_FAR
# Animations for the UNIT_FIELD_BYTES_1 stand states other than standing and dead.
const STAND_STATE_ANIMATIONS: Dictionary[int, String] = {
	1: "SitGround", 2: "SitChairLow", 3: "Sleep", 4: "SitChairLow", 5: "SitChairMed",
	6: "SitChairHigh", 8: "Kneel",
}

var in_combat: bool = false
var stand_state: int = 0

# Physics stays off until the ground under the player has loaded.
var active: bool = false:
	set(value):
		active = value
		set_physics_process(value)

var _flags: int = MoveFlag.NONE
# A server spline the player rides, as on a flight: points, distances along them, and timing.
var _path: PackedVector3Array = []
var _path_distances: PackedFloat32Array = []
var _path_elapsed: float = 0.0
var _path_duration: float = 0.0
var _heartbeat: float = 0.0
var _facing_timer: float = 0.0
var _facing_dirty: bool = false
var _mouse_turning: bool = false
var _orbiting: bool = false
var _fall_time: float = 0.0
var _fall_start_y: float = 0.0
var _jump_velocity: Vector3 = Vector3.ZERO
var _press_position: Vector2 = Vector2.ZERO
var _right_press_position: Vector2 = Vector2.ZERO
var _drag_distance: float = 0.0
var _model: Node3D
var _auto_run: bool = false

@onready var _model_slot: Node3D = $Model
@onready var _pivot: Node3D = $CameraPivot
@onready var _arm: SpringArm3D = $CameraPivot/SpringArm3D


func _ready() -> void:
	_arm.add_excluded_object(get_rid())
	_pivot.rotation.x = START_PITCH
	active = false


func _unhandled_input(event: InputEvent) -> void:
	if not _typing():
		if event.is_action_pressed("auto_run", false, true):
			get_viewport().set_input_as_handled()
			_auto_run = not _auto_run
		elif event.is_action_pressed("move_forward") or event.is_action_pressed("move_back"):
			_auto_run = false
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button:
		match button.button_index:
			MOUSE_BUTTON_RIGHT:
				_mouse_turning = button.pressed
				if button.pressed:
					_right_press_position = button.position
					_drag_distance = 0.0
					rotation.y += _pivot.rotation.y
					_pivot.rotation.y = 0.0
				elif _drag_distance < CLICK_SLOP:
					interacted.emit(_right_press_position)
			MOUSE_BUTTON_LEFT:
				_orbiting = button.pressed
				if button.pressed:
					_press_position = button.position
					_drag_distance = 0.0
				elif _drag_distance < CLICK_SLOP:
					clicked.emit(_press_position)
			MOUSE_BUTTON_WHEEL_UP:
				_arm.spring_length = maxf(_arm.spring_length / ZOOM_STEP, MIN_ZOOM)
			MOUSE_BUTTON_WHEEL_DOWN:
				_arm.spring_length = minf(_arm.spring_length * ZOOM_STEP, MAX_ZOOM)
		if not (_mouse_turning or _orbiting):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion and (_mouse_turning or _orbiting):
		_drag_distance += motion.relative.length()
		# Capturing only once a drag starts keeps plain clicks from grabbing the pointer.
		if _drag_distance >= CLICK_SLOP and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var pitch: float = _pivot.rotation.x - motion.relative.y * MOUSE_TURN
		_pivot.rotation.x = clampf(pitch, MIN_PITCH, MAX_PITCH)
		if _mouse_turning:
			rotation.y -= motion.relative.x * MOUSE_TURN
			_facing_dirty = true
		else:
			_pivot.rotation.y -= motion.relative.x * MOUSE_TURN


func _physics_process(delta: float) -> void:
	if not _path.is_empty():
		_ride(delta)
		return
	var flags: int = _input_flags()
	if flags & MoveFlag.TURN_LEFT:
		rotation.y += TURN_SPEED * delta
	elif flags & MoveFlag.TURN_RIGHT:
		rotation.y -= TURN_SPEED * delta

	if _flags & AIRBORNE:
		_fly(flags, delta)
	else:
		_walk(flags)
	_send_periodic(delta)
	_animate(_flags)


# A server path as on a flight, with no control until it ends; a resumed one starts partway along.
func follow_path(
	points: PackedVector3Array, duration_msec: int, elapsed_msec: int, from_start: bool,
) -> void:
	_path = PackedVector3Array() if from_start else PackedVector3Array([global_position])
	_path.append_array(points)
	_path_distances = PackedFloat32Array([0.0])
	for i: int in range(1, _path.size()):
		_path_distances.append(_path_distances[i - 1] + _path[i - 1].distance_to(_path[i]))
	_path_elapsed = elapsed_msec / 1000.0
	_path_duration = maxf(duration_msec / 1000.0, 0.001)
	_flags = MoveFlag.NONE
	velocity = Vector3.ZERO


func place(godot_position: Vector3, facing: float) -> void:
	global_position = godot_position
	rotation.y = facing


func set_model(model: Node3D) -> void:
	for child: Node in _model_slot.get_children():
		child.queue_free()
	_model_slot.add_child(model)
	_model = model


# WoW facing: 0 is north (+X) and it grows toward west (+Y), which matches Godot yaw here.
func orientation() -> float:
	return wrapf(rotation.y, 0.0, TAU)


func _walk(flags: int) -> void:
	var local: Vector3 = Vector3.ZERO
	if flags & MoveFlag.FORWARD:
		local.z -= 1.0
	elif flags & MoveFlag.BACKWARD:
		local.z += 1.0
	if flags & MoveFlag.STRAFE_LEFT:
		local.x -= 1.0
	elif flags & MoveFlag.STRAFE_RIGHT:
		local.x += 1.0
	var speed: float = BACK_SPEED if flags & MoveFlag.BACKWARD else RUN_SPEED
	var planar: Vector3 = (basis * local).normalized() * speed
	velocity = Vector3(planar.x, 0.0, planar.z)
	_send_changes(_flags, flags)
	_flags = flags
	if Input.is_action_just_pressed("jump") and not _typing():
		_take_off(flags, Vector3(planar.x, JUMP_VELOCITY, planar.z))
		_send("MSG_MOVE_JUMP", _flags)
	move_and_slide()
	if not is_on_floor() and not _flags & AIRBORNE:
		_take_off(flags, velocity)


# Airborne movement keeps the take-off velocity; only turning follows the keys until landing.
func _fly(flags: int, delta: float) -> void:
	_fall_time += delta
	velocity.x = _jump_velocity.x
	velocity.z = _jump_velocity.z
	velocity.y -= GRAVITY * delta
	move_and_slide()
	if is_on_floor() and velocity.y <= 0.0:
		_flags = flags
		_send("MSG_MOVE_FALL_LAND", _flags)
		_fall_time = 0.0
		return
	var airborne: int = (_flags & ~TURN) | (flags & TURN)
	if global_position.y < _fall_start_y:
		airborne |= MoveFlag.FALLING_FAR
	if (airborne & TURN) != (_flags & TURN):
		_send("MSG_MOVE_STOP_TURN" if not airborne & TURN else (
			"MSG_MOVE_START_TURN_LEFT" if airborne & MoveFlag.TURN_LEFT
			else "MSG_MOVE_START_TURN_RIGHT"
		), airborne)
	_flags = airborne


func _take_off(flags: int, take_off_velocity: Vector3) -> void:
	_flags = flags | MoveFlag.JUMPING
	_fall_time = 0.0
	_fall_start_y = global_position.y
	_jump_velocity = take_off_velocity
	velocity = take_off_velocity


func _typing() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit


func _input_flags() -> int:
	var flags: int = MoveFlag.NONE
	if _typing():
		return MoveFlag.FORWARD if _auto_run else flags
	# Autorun, and both mouse buttons held, run forward as in the stock client.
	if Input.is_action_pressed("move_forward") or _auto_run or (_mouse_turning and _orbiting):
		flags |= MoveFlag.FORWARD
	elif Input.is_action_pressed("move_back"):
		flags |= MoveFlag.BACKWARD
	var left: bool = Input.is_action_pressed("strafe_left")
	var right: bool = Input.is_action_pressed("strafe_right")
	# Holding the right mouse button turns the turn keys into strafes, as in the stock client.
	if _mouse_turning:
		left = left or Input.is_action_pressed("turn_left")
		right = right or Input.is_action_pressed("turn_right")
	elif Input.is_action_pressed("turn_left"):
		flags |= MoveFlag.TURN_LEFT
	elif Input.is_action_pressed("turn_right"):
		flags |= MoveFlag.TURN_RIGHT
	if left and not right:
		flags |= MoveFlag.STRAFE_LEFT
	elif right and not left:
		flags |= MoveFlag.STRAFE_RIGHT
	return flags


func _send_changes(old: int, new: int) -> void:
	if (old & LONGITUDINAL) != (new & LONGITUDINAL):
		if new & MoveFlag.FORWARD:
			_send("MSG_MOVE_START_FORWARD", new)
		elif new & MoveFlag.BACKWARD:
			_send("MSG_MOVE_START_BACKWARD", new)
		else:
			_send("MSG_MOVE_STOP", new)
	if (old & STRAFE) != (new & STRAFE):
		if new & MoveFlag.STRAFE_LEFT:
			_send("MSG_MOVE_START_STRAFE_LEFT", new)
		elif new & MoveFlag.STRAFE_RIGHT:
			_send("MSG_MOVE_START_STRAFE_RIGHT", new)
		else:
			_send("MSG_MOVE_STOP_STRAFE", new)
	if (old & TURN) != (new & TURN):
		if new & MoveFlag.TURN_LEFT:
			_send("MSG_MOVE_START_TURN_LEFT", new)
		elif new & MoveFlag.TURN_RIGHT:
			_send("MSG_MOVE_START_TURN_RIGHT", new)
		else:
			_send("MSG_MOVE_STOP_TURN", new)


func _send_periodic(delta: float) -> void:
	_heartbeat += delta
	if _flags != MoveFlag.NONE and _heartbeat >= HEARTBEAT_SECONDS:
		_send("MSG_MOVE_HEARTBEAT", _flags)
	_facing_timer += delta
	if _facing_dirty and _facing_timer >= FACING_SECONDS:
		_facing_dirty = false
		_facing_timer = 0.0
		_send("MSG_MOVE_SET_FACING", _flags)


func _send(opcode: String, flags: int) -> void:
	_heartbeat = 0.0
	var fall_msec: int = roundi(_fall_time * 1000.0)
	movement_changed.emit(opcode, global_position, orientation(), flags, fall_msec, _jump_velocity)


func play_once(candidates: PackedStringArray) -> void:
	if _model:
		UnitAnimations.play_once(_model, candidates)


func set_dead(dead: bool) -> void:
	if _model == null or dead == UnitAnimations.is_dead(_model):
		return
	if dead:
		UnitAnimations.die(_model)
	else:
		UnitAnimations.revive(_model)


func _ride(delta: float) -> void:
	_path_elapsed += delta
	var total: float = _path_distances[_path_distances.size() - 1]
	var travelled: float = total * clampf(_path_elapsed / _path_duration, 0.0, 1.0)
	var index: int = clampi(_path_distances.bsearch(travelled), 1, _path.size() - 1)
	var span: float = maxf(_path_distances[index] - _path_distances[index - 1], 0.001)
	var weight: float = (travelled - _path_distances[index - 1]) / span
	global_position = _path[index - 1].lerp(_path[index], clampf(weight, 0.0, 1.0))
	var heading: Vector3 = _path[index] - _path[index - 1]
	if Vector2(heading.x, heading.z).length() > 0.01:
		rotation.y = atan2(-heading.x, -heading.z)
	if _model:
		UnitAnimations.set_base(_model, ["Fly", "Run"])
	if _path_elapsed >= _path_duration:
		_path.clear()


func _animate(flags: int) -> void:
	if _model == null:
		return
	var moving: PackedStringArray = UnitAnimations.movement_clips(flags)
	if not moving.is_empty():
		UnitAnimations.set_base(_model, moving)
	elif STAND_STATE_ANIMATIONS.has(stand_state):
		UnitAnimations.set_base(_model, [STAND_STATE_ANIMATIONS[stand_state]])
	elif in_combat:
		UnitAnimations.set_base(_model, UnitAnimations.READY)
	else:
		UnitAnimations.set_base(_model, ["Stand"])
