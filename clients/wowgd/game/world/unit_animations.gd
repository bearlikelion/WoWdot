class_name UnitAnimations
extends RefCounted

# Candidates in order: clips follow AnimationData.dbc names and not every model has each one.
const ATTACK: PackedStringArray = ["Attack1H", "AttackUnarmed", "Attack2H", "Attack1HPierce"]
const READY: PackedStringArray = ["Ready1H", "ReadyUnarmed", "Ready2H"]
const WOUND: PackedStringArray = ["CombatWound", "CombatCritical"]
const DEATH: PackedStringArray = ["Death"]
const BLEND: float = 0.15
const BASE_META: StringName = &"base_animation"
const BUSY_META: StringName = &"one_shot_until"
const DEAD_META: StringName = &"dead"


# The looping clip the model returns to between one-shots, such as Stand, Run or a ready stance.
static func set_base(model: Node3D, candidates: PackedStringArray) -> void:
	var player: AnimationPlayer = _player(model)
	if player == null or model.get_meta(DEAD_META, false):
		return
	var clip: String = _first(player, candidates)
	if clip.is_empty():
		return
	model.set_meta(BASE_META, clip)
	UnitVoice.set_gait(model, clip)
	if Time.get_ticks_msec() >= int(model.get_meta(BUSY_META, 0)) and player.current_animation != clip:
		player.play(clip, BLEND)


static func play_once(model: Node3D, candidates: PackedStringArray) -> void:
	var player: AnimationPlayer = _player(model)
	if player == null or model.get_meta(DEAD_META, false):
		return
	var clip: String = _first(player, candidates)
	if clip.is_empty():
		return
	var length: float = player.get_animation(clip).length
	model.set_meta(BUSY_META, Time.get_ticks_msec() + int(length * 1000.0))
	player.play(clip, BLEND)
	player.seek(0.0, true)
	model.get_tree().create_timer(length).timeout.connect(
		_return_to_base.bind(model.get_instance_id(), clip)
	)


# Plays the death clip and holds its last frame until revive() clears it.
static func die(model: Node3D) -> void:
	var player: AnimationPlayer = _player(model)
	if player == null or model.get_meta(DEAD_META, false):
		return
	var clip: String = _first(player, DEATH)
	model.set_meta(DEAD_META, true)
	UnitVoice.set_gait(model, "")
	if clip.is_empty():
		return
	player.play(clip, BLEND)
	var length: float = player.get_animation(clip).length
	model.get_tree().create_timer(length).timeout.connect(_hold.bind(model.get_instance_id(), clip))


static func revive(model: Node3D) -> void:
	model.set_meta(DEAD_META, false)
	var player: AnimationPlayer = _player(model)
	if player:
		player.play(String(model.get_meta(BASE_META, "Stand")), BLEND)


static func is_dead(model: Node3D) -> bool:
	return model.get_meta(DEAD_META, false)


# The clips a unit moving with these MSG_MOVE flags plays; empty while it stands still.
static func movement_clips(flags: int) -> PackedStringArray:
	var travelling: bool = flags & (Player.LONGITUDINAL | Player.STRAFE) != 0
	if flags & Player.MoveFlag.FALLING_FAR:
		return ["Fall"]
	if flags & Player.MoveFlag.JUMPING:
		return ["Jump"]
	if flags & Player.MoveFlag.SWIMMING:
		return ["Swim"] if travelling else ["SwimIdle"]
	if flags & Player.MoveFlag.FORWARD:
		return ["Walk"] if flags & Player.MoveFlag.WALK_MODE else ["Run"]
	if flags & Player.MoveFlag.BACKWARD:
		return ["Walkbackwards"]
	if flags & Player.MoveFlag.STRAFE_LEFT:
		return ["ShuffleLeft"]
	if flags & Player.MoveFlag.STRAFE_RIGHT:
		return ["ShuffleRight"]
	return []


# Timers carry the instance id because the model may be freed (respawned) before they fire.
static func _return_to_base(model_id: int, clip: String) -> void:
	var model: Node3D = instance_from_id(model_id) as Node3D
	if model == null or model.get_meta(DEAD_META, false):
		return
	var player: AnimationPlayer = _player(model)
	if player and player.current_animation == clip:
		player.play(String(model.get_meta(BASE_META, "Stand")), BLEND)


static func _hold(model_id: int, clip: String) -> void:
	var model: Node3D = instance_from_id(model_id) as Node3D
	if model == null:
		return
	var player: AnimationPlayer = _player(model)
	if player and player.current_animation == clip and model.get_meta(DEAD_META, false):
		player.pause()


static func _player(model: Node3D) -> AnimationPlayer:
	return model.get_node_or_null("AnimationPlayer") if is_instance_valid(model) else null


static func _first(player: AnimationPlayer, candidates: PackedStringArray) -> String:
	for clip: String in candidates:
		if player.has_animation(clip):
			return clip
	return ""
