class_name Player
extends CharacterBody3D

# jump_velocity is the take-off velocity, which WoW keeps for the whole jump or fall.
# An ack_counter of 0 or more answers a server movement change, with ack_tail appended.
signal movement_changed(
	opcode: String, godot_position: Vector3, orientation: float, flags: int,
	fall_time_msec: int, jump_velocity: Vector3, ack_counter: int, ack_tail: PackedByteArray,
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
	# Not 1.12 bits: the session moves them to where 3.3.5 keeps them.
	FLYING = 0x800000,
	CAN_FLY = 0x1000000,
	ONTRANSPORT = 0x2000000,
	WATERWALKING = 0x10000000,
	SAFE_FALL = 0x20000000,
	HOVER = 0x40000000,
}
# The order of WowSession.get_object_speeds.
enum SpeedKind { WALK, RUN, RUN_BACK, SWIM, SWIM_BACK, TURN_RATE, FLIGHT, FLIGHT_BACK }

const DEFAULT_SPEEDS: PackedFloat32Array = [2.5, 7.0, 4.5, 4.722222, 2.5, 3.141594, 7.0, 4.5]
const SPEED_ACKS: Dictionary[SpeedKind, String] = {
	SpeedKind.WALK: "CMSG_FORCE_WALK_SPEED_CHANGE_ACK",
	SpeedKind.RUN: "CMSG_FORCE_RUN_SPEED_CHANGE_ACK",
	SpeedKind.RUN_BACK: "CMSG_FORCE_RUN_BACK_SPEED_CHANGE_ACK",
	SpeedKind.SWIM: "CMSG_FORCE_SWIM_SPEED_CHANGE_ACK",
	SpeedKind.SWIM_BACK: "CMSG_FORCE_SWIM_BACK_SPEED_CHANGE_ACK",
	SpeedKind.FLIGHT: "CMSG_FORCE_FLIGHT_SPEED_CHANGE_ACK",
	SpeedKind.FLIGHT_BACK: "CMSG_FORCE_FLIGHT_BACK_SPEED_CHANGE_ACK",
}
const FLAG_ACKS: Dictionary[MoveFlag, String] = {
	MoveFlag.WATERWALKING: "CMSG_MOVE_WATER_WALK_ACK",
	MoveFlag.SAFE_FALL: "CMSG_MOVE_FEATHER_FALL_ACK",
	MoveFlag.HOVER: "CMSG_MOVE_HOVER_ACK",
	MoveFlag.CAN_FLY: "CMSG_MOVE_SET_CAN_FLY_ACK",
}
const GRAVITY: float = 19.29
# Slow Fall and Levitate drift down at this speed rather than under full gravity.
const FEATHER_FALL_SPEED: float = 7.0
const JUMP_VELOCITY: float = 7.95797334
# The tallest lip walked over without a jump; tune against stock stairs and kerbs.
const STEP_HEIGHT: float = 0.6
const HEARTBEAT_SECONDS: float = 0.5
const FACING_SECONDS: float = 0.2
const MOUSE_TURN: float = 0.006
const START_PITCH: float = -0.3
# Water this deep over the feet starts a swim, and a little less ends it.
const SWIM_ENTER: float = 1.5
const SWIM_EXIT: float = 1.3
# How far the shoulders stay under while swimming at the surface.
const SWIM_SURFACE: float = 1.4
# Transports.watch marks their nodes with this, so a foot on one can name it.
const TRANSPORT_META: StringName = &"transport_guid"
const FLOAT_SPEED: float = 1.0
const MIN_PITCH: float = -1.3
const MAX_PITCH: float = 0.6
const MIN_ZOOM: float = 1.5
# The stock default; its Max Camera Distance slider doubles this at most.
const MAX_ZOOM: float = 15.0
const ZOOM_STEP: float = 1.2
# A driven vehicle keeps the camera this many of its radii back, so it never sits inside the hull.
const VEHICLE_ZOOM: float = 2.5
const CLICK_SLOP: float = 4.0
const LONGITUDINAL: int = MoveFlag.FORWARD | MoveFlag.BACKWARD
const STRAFE: int = MoveFlag.STRAFE_LEFT | MoveFlag.STRAFE_RIGHT
const TURN: int = MoveFlag.TURN_LEFT | MoveFlag.TURN_RIGHT
const AIRBORNE: int = MoveFlag.JUMPING | MoveFlag.FALLING_FAR
# States the server switches on and off, which say nothing about motion.
const PERSISTENT: int = MoveFlag.ROOT | MoveFlag.WATERWALKING | MoveFlag.SAFE_FALL | MoveFlag.HOVER \
		| MoveFlag.CAN_FLY
# Animations for the UNIT_FIELD_BYTES_1 stand states other than standing and dead.
const STAND_STATE_ANIMATIONS: Dictionary[int, String] = {
	1: "SitGround", 2: "SitChairLow", 3: "Sleep", 4: "SitChairLow", 5: "SitChairMed",
	6: "SitChairHigh", 8: "Kneel",
}

var in_combat: bool = false
# Cleared by SMSG_CLIENT_CONTROL_UPDATE while the server moves the player (fear, charm).
var controllable: bool = true
var stand_state: int = 0

# Physics stays off until the ground under the player has loaded.
var active: bool = false:
	set(value):
		active = value
		set_physics_process(value)
		set_process(value)

var _flags: int = MoveFlag.NONE
var _persistent: int = MoveFlag.NONE
var _speeds: PackedFloat32Array = DEFAULT_SPEEDS
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
var _ascending: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _right_press_position: Vector2 = Vector2.ZERO
var _drag_distance: float = 0.0
var _min_zoom: float = MIN_ZOOM
var _pivot_height: float = 0.0
var _model: Node3D
var _auto_run: bool = false
# The liquid surface over the player, set by the world each frame, NAN where there is none.
var _water_surface: float = NAN
var _transport: Node3D
var _transport_guid: int = 0
var _transport_offset: Vector3 = Vector3.ZERO

@onready var _collision: CollisionShape3D = $Collision
@onready var _model_slot: Node3D = $Model
@onready var _pivot: Node3D = $CameraPivot
@onready var _arm: SpringArm3D = $CameraPivot/SpringArm3D
# WoW hears from the character, not the camera, so zooming out does not muffle the world.
@onready var _ear: AudioListener3D = $CameraPivot/Ear


func _ready() -> void:
	_arm.add_excluded_object(get_rid())
	_pivot.rotation.x = START_PITCH
	_ear.make_current()
	UnitVoice.listener = _ear
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
				_arm.spring_length = maxf(_arm.spring_length / ZOOM_STEP, _min_zoom)
			MOUSE_BUTTON_WHEEL_DOWN:
				_arm.spring_length = minf(_arm.spring_length * ZOOM_STEP, maxf(MAX_ZOOM, _min_zoom))
		if not (_mouse_turning or _orbiting):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion and (_mouse_turning or _orbiting):
		_drag_distance += motion.relative.length()
		# Capturing only once a drag starts keeps plain clicks from grabbing the pointer.
		if _drag_distance >= CLICK_SLOP and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var sign_y: float = -1.0 if WowAssets.interface.is_on(&"invert_mouse") else 1.0
		var tilt: float = _pivot.rotation.x - motion.relative.y * MOUSE_TURN * sign_y
		_pivot.rotation.x = clampf(tilt, MIN_PITCH, MAX_PITCH)
		if _mouse_turning:
			rotation.y -= motion.relative.x * MOUSE_TURN
			_facing_dirty = true
		else:
			_pivot.rotation.y -= motion.relative.x * MOUSE_TURN


# Keyboard turning runs every frame, so the camera it carries does not step at the physics rate.
func _process(delta: float) -> void:
	if not _path.is_empty():
		return
	var flags: int = _input_flags()
	if flags & MoveFlag.TURN_LEFT:
		rotation.y += _speeds[SpeedKind.TURN_RATE] * delta
	elif flags & MoveFlag.TURN_RIGHT:
		rotation.y -= _speeds[SpeedKind.TURN_RATE] * delta


func _physics_process(delta: float) -> void:
	if not _path.is_empty():
		_ride(delta)
		return
	_ride_transport()
	var flags: int = _input_flags()
	if flags & MoveFlag.ROOT:
		_send_changes(_flags, flags)
		_flags = flags
	elif _swimming():
		_swim(flags)
	elif _flags & MoveFlag.FLYING:
		_flight(flags)
	elif _flags & AIRBORNE:
		_fly(flags, delta)
	else:
		_walk(flags)
	_hold_transport()
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


# The transport the player stands on, and where on it, which the server needs with every move.
func transport_guid() -> int:
	return _transport_guid


# A lift answers here but not to transport_guid(), being only a platform on the client.
func on_transport() -> bool:
	return _transport != null


func transport_offset() -> Vector3:
	return _transport_offset


func transport_orientation() -> float:
	return rotation.y - _transport.rotation.y if _transport else 0.0


# The transport carries the player before the keys do, which is what standing on a deck means.
func _ride_transport() -> void:
	if _transport == null:
		return
	if not is_instance_valid(_transport):
		_transport = null
		_transport_guid = 0
		return
	global_position = _transport.global_transform * _transport_offset


# Whatever the feet came down on this frame decides the transport, and the offset follows from it.
func _hold_transport() -> void:
	var found: Node3D = null
	for i: int in get_slide_collision_count():
		var node: Node = get_slide_collision(i).get_collider() as Node
		while node:
			if node.has_meta(TRANSPORT_META):
				found = node as Node3D
				break
			node = node.get_parent()
		if found:
			break
	_transport = found
	_transport_guid = found.get_meta(TRANSPORT_META) if found else 0
	if found:
		_transport_offset = found.global_transform.affine_inverse() * global_position


func set_water_surface(surface: float) -> void:
	_water_surface = surface


func water_surface() -> float:
	return _water_surface


# WoW sends the camera's pitch while swimming, positive looking up.
func pitch() -> float:
	return _pivot.rotation.x


# Puts the player on a deck at the server's boat-local pose, as a crossing lands them.
func board(transport: Node3D, wire_guid: int, offset: Vector3, facing: float) -> void:
	_transport = transport
	_transport_guid = wire_guid
	_transport_offset = offset
	global_position = transport.global_transform * offset
	rotation.y = transport.rotation.y + facing


func place(godot_position: Vector3, facing: float) -> void:
	# Being put somewhere else ends the ride, or the deck drags them back the very next frame.
	_transport = null
	_transport_guid = 0
	global_position = godot_position
	rotation.y = facing


# Turns to look at a spot, as the stock client does when a spell needs the target in front.
func face(spot: Vector3) -> void:
	var away: Vector3 = spot - global_position
	if away.length_squared() < 0.01:
		return
	rotation.y = atan2(-away.x, -away.z)
	_facing_dirty = true


func set_speeds(speeds: PackedFloat32Array) -> void:
	if speeds.size() == DEFAULT_SPEEDS.size():
		_speeds = speeds


func force_speed(kind: SpeedKind, speed: float, counter: int) -> void:
	_speeds[kind] = speed
	var tail: PackedByteArray = []
	tail.resize(4)
	tail.encode_float(0, speed)
	_send(SPEED_ACKS[kind], _flags, counter, tail)


# A 1.12 client rooted mid-jump hangs in the air until the root ends.
# Mounting changes the collision height, which the server wants acknowledged like a speed.
func ack_collision_height(height: float, counter: int) -> void:
	var tail: PackedByteArray = []
	tail.resize(4)
	tail.encode_float(0, height)
	_send("CMSG_MOVE_SET_COLLISION_HGT_ACK", _flags, counter, tail)


func force_flag(flag: MoveFlag, apply: bool, counter: int) -> void:
	_persistent = (_persistent & ~flag) | (flag if apply else MoveFlag.NONE)
	if flag == MoveFlag.ROOT:
		_flags = ((_flags & TURN) if apply else (_flags & ~flag)) | _persistent
		velocity = Vector3.ZERO
		_fall_time = 0.0
		var ack: String = "CMSG_FORCE_MOVE_ROOT_ACK" if apply else "CMSG_FORCE_MOVE_UNROOT_ACK"
		_send(ack, _flags, counter)
		return
	_flags = (_flags & ~flag) | (flag if apply else MoveFlag.NONE)
	var tail: PackedByteArray = []
	tail.resize(4)
	tail.encode_u32(0, 1 if apply else 0)
	_send(FLAG_ACKS[flag], _flags, counter, tail)


func knock_back(take_off_velocity: Vector3, counter: int) -> void:
	_take_off(_flags & ~(LONGITUDINAL | STRAFE), take_off_velocity)
	_send("CMSG_MOVE_KNOCK_BACK_ACK", _flags, counter)


# Frames a driven vehicle from its top and past its radius; zero sizes put the player's view back.
func frame_vehicle(height: float, radius: float) -> void:
	if _pivot_height == 0.0:
		_pivot_height = _pivot.position.y
	_pivot.position.y = height if height > 0.0 else _pivot_height
	_min_zoom = maxf(radius * VEHICLE_ZOOM, MIN_ZOOM)
	_arm.spring_length = clampf(_arm.spring_length, _min_zoom, maxf(MAX_ZOOM, _min_zoom))


func set_model(body: Node3D) -> void:
	for child: Node in _model_slot.get_children():
		child.queue_free()
	_model_slot.add_child(body)
	_model = body


func model() -> Node3D:
	return _model


# WoW facing: 0 is north (+X) and it grows toward west (+Y), which matches Godot yaw here.
# The top of the capsule the player moves in, for anything drawn over their head.
func head_position() -> Vector3:
	return global_position + Vector3.UP * (_collision.shape as CapsuleShape3D).height


func orientation() -> float:
	return wrapf(rotation.y, 0.0, TAU)


func _walk(flags: int) -> void:
	if _flags & MoveFlag.SWIMMING:
		_flags &= ~MoveFlag.SWIMMING
		_send("MSG_MOVE_STOP_SWIM", _flags)
	var local: Vector3 = Vector3.ZERO
	if flags & MoveFlag.FORWARD:
		local.z -= 1.0
	elif flags & MoveFlag.BACKWARD:
		local.z += 1.0
	if flags & MoveFlag.STRAFE_LEFT:
		local.x -= 1.0
	elif flags & MoveFlag.STRAFE_RIGHT:
		local.x += 1.0
	var speed: float = _speeds[SpeedKind.RUN_BACK if flags & MoveFlag.BACKWARD else SpeedKind.RUN]
	var planar: Vector3 = (basis * local).normalized() * speed
	velocity = Vector3(planar.x, 0.0, planar.z)
	_send_changes(_flags, flags)
	_flags = flags
	if Input.is_action_just_pressed("jump") and controllable and not _typing():
		if _persistent & MoveFlag.CAN_FLY:
			return _start_flight(flags)
		_take_off(flags, Vector3(planar.x, JUMP_VELOCITY, planar.z))
		_send("MSG_MOVE_JUMP", _flags)
	_step_up(velocity)
	move_and_slide()
	if not is_on_floor() and not _flags & AIRBORNE:
		_take_off(flags, velocity)


# A capsule only slides over lips lower than its rounded foot, so taller ones are climbed by hand.
func _step_up(planar: Vector3) -> void:
	var motion: Vector3 = planar * get_physics_process_delta_time()
	if motion.is_zero_approx() or not is_on_floor() or not test_move(global_transform, motion):
		return
	var lift: Vector3 = Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, lift):
		return
	var raised: Transform3D = global_transform.translated(lift)
	# One frame's motion ends on the step's edge, so the tread is judged a foot's width further in.
	var reach: Vector3 = motion.normalized() * (_collision.shape as CapsuleShape3D).radius
	var tread: KinematicCollision3D = KinematicCollision3D.new()
	if test_move(raised, reach) or not test_move(raised.translated(reach), -lift, tread):
		return
	if tread.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return
	var drop: KinematicCollision3D = KinematicCollision3D.new()
	test_move(raised.translated(motion), -lift, drop)
	# Only the height changes here; move_and_slide then carries the player onto the tread.
	global_position += lift + drop.get_travel()


func _swimming() -> bool:
	if is_nan(_water_surface):
		return false
	var depth: float = _water_surface - global_position.y
	return depth > (SWIM_EXIT if _flags & MoveFlag.SWIMMING else SWIM_ENTER)


# Swimming follows the camera's pitch, and floats up to the surface when nothing is held.
func _swim(flags: int) -> void:
	flags |= MoveFlag.SWIMMING
	var local: Vector3 = Vector3.ZERO
	if flags & MoveFlag.STRAFE_LEFT:
		local.x -= 1.0
	elif flags & MoveFlag.STRAFE_RIGHT:
		local.x += 1.0
	var direction: Vector3 = basis * local
	var forward: Vector3 = -basis.z * cos(pitch()) + Vector3.UP * sin(pitch())
	if flags & MoveFlag.FORWARD:
		direction += forward
	elif flags & MoveFlag.BACKWARD:
		direction -= forward
	var kind: SpeedKind = SpeedKind.SWIM_BACK if flags & MoveFlag.BACKWARD else SpeedKind.SWIM
	velocity = direction.normalized() * _speeds[kind]
	if not flags & LONGITUDINAL:
		velocity.y = FLOAT_SPEED
	if not _flags & MoveFlag.SWIMMING:
		_flags = flags
		_send("MSG_MOVE_START_SWIM", flags)
	_send_changes(_flags, flags)
	_flags = flags
	move_and_slide()
	var ceiling: float = _water_surface - SWIM_SURFACE
	if global_position.y > ceiling:
		global_position.y = ceiling
	_fall_time = 0.0
	_jump_velocity = Vector3.ZERO


func _start_flight(flags: int) -> void:
	_flags = (flags & ~AIRBORNE) | MoveFlag.FLYING
	_fall_time = 0.0
	_send("CMSG_MOVE_SET_FLY", _flags)
	_send("MSG_MOVE_START_ASCEND", _flags)
	_ascending = true


# Flight steers by the camera's pitch like swimming; jump climbs, and touching ground lands.
func _flight(flags: int) -> void:
	if not _persistent & MoveFlag.CAN_FLY:
		_flags &= ~MoveFlag.FLYING
		_send("CMSG_MOVE_SET_FLY", _flags)
		_take_off(_flags, Vector3.ZERO)
		return
	flags |= MoveFlag.FLYING
	var local: Vector3 = Vector3.ZERO
	if flags & MoveFlag.STRAFE_LEFT:
		local.x -= 1.0
	elif flags & MoveFlag.STRAFE_RIGHT:
		local.x += 1.0
	var direction: Vector3 = basis * local
	var forward: Vector3 = -basis.z * cos(pitch()) + Vector3.UP * sin(pitch())
	if flags & MoveFlag.FORWARD:
		direction += forward
	elif flags & MoveFlag.BACKWARD:
		direction -= forward
	var kind: SpeedKind = SpeedKind.FLIGHT_BACK if flags & MoveFlag.BACKWARD else SpeedKind.FLIGHT
	velocity = direction.normalized() * _speeds[kind]
	var climbing: bool = Input.is_action_pressed("jump") and controllable and not _typing()
	if climbing:
		velocity.y = _speeds[SpeedKind.FLIGHT]
	if climbing != _ascending:
		_ascending = climbing
		_send("MSG_MOVE_START_ASCEND" if climbing else "MSG_MOVE_STOP_ASCEND", flags)
	_send_changes(_flags, flags)
	_flags = flags
	move_and_slide()
	_fall_time = 0.0
	if is_on_floor() and velocity.y <= 0.0:
		_flags &= ~MoveFlag.FLYING
		_send("CMSG_MOVE_SET_FLY", _flags)


# Airborne movement keeps the take-off velocity; only turning follows the keys until landing.
func _fly(flags: int, delta: float) -> void:
	if _persistent & MoveFlag.CAN_FLY and Input.is_action_just_pressed("jump") and controllable \
	and not _typing():
		return _start_flight(flags)
	_fall_time += delta
	velocity.x = _jump_velocity.x
	velocity.z = _jump_velocity.z
	velocity.y -= GRAVITY * delta
	if _persistent & (MoveFlag.SAFE_FALL | MoveFlag.HOVER):
		velocity.y = maxf(velocity.y, -FEATHER_FALL_SPEED)
	move_and_slide()
	if _swimming():
		return
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
	var flags: int = _key_flags()
	if _persistent & MoveFlag.ROOT:
		flags &= TURN
	if _transport_guid != 0:
		flags |= MoveFlag.ONTRANSPORT
	return flags | _persistent


func _key_flags() -> int:
	var flags: int = MoveFlag.NONE
	if not controllable:
		return flags
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
	if _flags & ~PERSISTENT and _heartbeat >= HEARTBEAT_SECONDS:
		_send("MSG_MOVE_HEARTBEAT", _flags)
	_facing_timer += delta
	if _facing_dirty and _facing_timer >= FACING_SECONDS:
		_facing_dirty = false
		_facing_timer = 0.0
		_send("MSG_MOVE_SET_FACING", _flags)


func _send(
	opcode: String, flags: int, ack_counter: int = -1, ack_tail: PackedByteArray = [],
) -> void:
	_heartbeat = 0.0
	var fall_msec: int = roundi(_fall_time * 1000.0)
	movement_changed.emit(
		opcode, global_position, orientation(), flags, fall_msec, _jump_velocity,
		ack_counter, ack_tail,
	)


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
