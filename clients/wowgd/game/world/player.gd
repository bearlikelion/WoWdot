class_name Player
extends CharacterBody3D

signal movement_changed(opcode: String, godot_position: Vector3, orientation: float, flags: int)
# A left press and release that did not orbit the camera.
signal clicked(screen_position: Vector2)

enum MoveFlag {
	NONE = 0,
	FORWARD = 0x1,
	BACKWARD = 0x2,
	STRAFE_LEFT = 0x4,
	STRAFE_RIGHT = 0x8,
	TURN_LEFT = 0x10,
	TURN_RIGHT = 0x20,
}

const RUN_SPEED: float = 7.0
const BACK_SPEED: float = 4.5
const TURN_SPEED: float = PI
const GRAVITY: float = 19.29
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

# Physics stays off until the ground under the player has loaded.
var active: bool = false:
	set(value):
		active = value
		set_physics_process(value)

var _flags: int = MoveFlag.NONE
var _heartbeat: float = 0.0
var _facing_timer: float = 0.0
var _facing_dirty: bool = false
var _mouse_turning: bool = false
var _orbiting: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _drag_distance: float = 0.0
var _animation: AnimationPlayer

@onready var _model_slot: Node3D = $Model
@onready var _pivot: Node3D = $CameraPivot
@onready var _arm: SpringArm3D = $CameraPivot/SpringArm3D


func _ready() -> void:
	_arm.add_excluded_object(get_rid())
	_pivot.rotation.x = START_PITCH
	active = false


func _unhandled_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button:
		match button.button_index:
			MOUSE_BUTTON_RIGHT:
				_mouse_turning = button.pressed
				if button.pressed:
					_drag_distance = 0.0
					rotation.y += _pivot.rotation.y
					_pivot.rotation.y = 0.0
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
	var flags: int = _input_flags()
	if flags & MoveFlag.TURN_LEFT:
		rotation.y += TURN_SPEED * delta
	elif flags & MoveFlag.TURN_RIGHT:
		rotation.y -= TURN_SPEED * delta

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
	velocity.x = planar.x
	velocity.z = planar.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()

	_send_changes(_flags, flags)
	_flags = flags
	_send_periodic(delta)
	_animate(flags)


func place(godot_position: Vector3, facing: float) -> void:
	global_position = godot_position
	rotation.y = facing


func set_model(model: Node3D) -> void:
	for child: Node in _model_slot.get_children():
		child.queue_free()
	_model_slot.add_child(model)
	_animation = model.get_node_or_null("AnimationPlayer")


# WoW facing: 0 is north (+X) and it grows toward west (+Y), which matches Godot yaw here.
func orientation() -> float:
	return wrapf(rotation.y, 0.0, TAU)


func _input_flags() -> int:
	var flags: int = MoveFlag.NONE
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return flags
	if Input.is_action_pressed("move_forward"):
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
	movement_changed.emit(opcode, global_position, orientation(), flags)


func _animate(flags: int) -> void:
	if _animation == null:
		return
	var wanted: String = "Stand"
	if flags & MoveFlag.FORWARD:
		wanted = "Run"
	elif flags & MoveFlag.BACKWARD:
		wanted = "Walkbackwards"
	elif flags & MoveFlag.STRAFE_LEFT:
		wanted = "ShuffleLeft"
	elif flags & MoveFlag.STRAFE_RIGHT:
		wanted = "ShuffleRight"
	if _animation.current_animation != wanted and _animation.has_animation(wanted):
		_animation.play(wanted, 0.15)
