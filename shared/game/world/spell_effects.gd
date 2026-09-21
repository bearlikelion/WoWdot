class_name SpellEffects
extends Node3D

# An effect with no animation of its own still leaves the screen.
const FALLBACK_SECONDS: float = 1.5
# A spell with no speed in Spell.dbc lands the moment it goes off.
const INSTANT_SPEED: float = 0.0
const UNIT_DYNFLAG_LOOTABLE: int = 0x1

@export var shake: CameraShake

var _entities: Entities
var _player: Player
# Caster guid to the precast effects hanging on them until the cast ends.
var _casting: Dictionary[int, Array] = {}
# Caster guid to the clip they hold while the cast runs.
var _posing: Dictionary[int, String] = {}
var _sparkles: Dictionary[int, Node3D] = {}
var _missiles: Array[Dictionary] = []


func _ready() -> void:
	var session: WowSession = WowClient.session
	session.spell_cast_started.connect(_on_cast_started)
	session.spell_cast_finished.connect(_on_cast_finished)
	session.spell_cast_failed.connect(_on_cast_failed)
	session.object_updated.connect(_on_object_updated)
	session.objects_destroyed.connect(_on_objects_destroyed)
	session.packet_received.connect(_on_packet_received)


func _process(delta: float) -> void:
	for i: int in range(_missiles.size() - 1, -1, -1):
		if not _advance(_missiles[i], delta):
			_missiles.remove_at(i)
	for caster: int in _posing:
		var model: Node3D = _model_of(caster)
		if model:
			UnitAnimations.hold(model, [_posing[caster]])


func watch(entities: Entities, player: Player) -> void:
	_entities = entities
	_player = player


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode == "SMSG_PLAY_SPELL_VISUAL" and payload.size() >= 12:
		var effects: Array[Dictionary] = WowAssets.spell_visuals.kit_effects(payload.decode_u32(8))
		_hang_effects(payload.decode_u64(0), effects, FALLBACK_SECONDS)


func _on_cast_started(caster: int, spell_id: int, _cast_time_msec: int) -> void:
	_drop_precast(caster)
	_casting[caster] = _hang(caster, spell_id, SpellVisuals.Kit.PRECAST, 0.0)
	var pose: String = WowAssets.spell_visuals.animation(spell_id, SpellVisuals.Kit.PRECAST)
	if not pose.is_empty():
		_posing[caster] = pose


func _on_cast_finished(caster: int, spell_id: int, targets: PackedInt64Array) -> void:
	_drop_precast(caster)
	_hang(caster, spell_id, SpellVisuals.Kit.CAST, FALLBACK_SECONDS)
	_play(caster, WowAssets.spell_visuals.animation(spell_id, SpellVisuals.Kit.CAST))
	var visuals: SpellVisuals = WowAssets.spell_visuals
	for target: int in targets:
		if visuals.has_missile(spell_id) and target != caster:
			_launch(caster, target, spell_id)
		else:
			_impact(target, spell_id)


func _on_cast_failed(caster: int, _spell_id: int, _reason: int) -> void:
	_drop_precast(caster)


func _on_object_updated(guid: int) -> void:
	var session: WowSession = WowClient.session
	var lootable: bool = session.get_field(guid, "UNIT_FIELD_HEALTH") == 0 \
	and session.get_field(guid, "UNIT_DYNAMIC_FLAGS") & UNIT_DYNFLAG_LOOTABLE != 0
	if lootable == _sparkles.has(guid):
		return
	if not lootable:
		_clear_sparkle(guid)
		return
	var sparkle: Node3D = _mount(guid, WowAssets.spell_visuals.loot_sparkle(), [19])
	if sparkle:
		_sparkles[guid] = sparkle


func _on_objects_destroyed(guids: PackedInt64Array) -> void:
	for guid: int in guids:
		_clear_sparkle(guid)
		_casting.erase(guid)


# A model played once on the unit and taken down when its sequence ends, such as the level up glow.
func flourish(guid: int, path: String, seconds: float) -> Node3D:
	var model: Node3D = _mount(guid, path, [])
	if model != null:
		_expire(model, maxf(seconds, _length(model)))
	return model


# What landing on the target looks like: the kit's effects and the flinch it names.
func _impact(target: int, spell_id: int) -> void:
	_hang(target, spell_id, SpellVisuals.Kit.IMPACT, FALLBACK_SECONDS)
	_play(target, WowAssets.spell_visuals.animation(spell_id, SpellVisuals.Kit.IMPACT))


# Plays a clip once on whatever the unit is drawn as.
func _play(guid: int, clip: String) -> void:
	var model: Node3D = _model_of(guid)
	if model and not clip.is_empty():
		UnitAnimations.play_once(model, [clip])


# Hangs a stage's models on the unit, giving them back so a precast can be taken down again.
func _hang(guid: int, spell_id: int, kit: SpellVisuals.Kit, seconds: float) -> Array:
	var shaken: Node3D = _model_of(guid)
	if shaken and shake:
		shake.add_group(WowAssets.spell_visuals.shake_group(spell_id, kit), shaken.global_position)
	return _hang_effects(guid, WowAssets.spell_visuals.effects(spell_id, kit), seconds)


func _hang_effects(guid: int, effects: Array[Dictionary], seconds: float) -> Array:
	var hung: Array = []
	for effect: Dictionary in effects:
		var model: Node3D = _mount(guid, effect["path"], effect["points"])
		if model == null:
			continue
		hung.append(model)
		if seconds > 0.0:
			_expire(model, maxf(seconds, _length(model)))
	return hung


# Loads the effect and hangs it on the first attachment point the unit carries.
func _mount(guid: int, path: String, points: Array) -> Node3D:
	var host: Node3D = _model_of(guid)
	if host == null or path.is_empty():
		return null
	var model: Node3D = WowAssets.loader.load_m2(path)
	if model == null:
		return null
	RibbonTrail.attach(model, path)
	CreatureModels.mark_unit(model)
	UnitAnimations.set_base(model, ["Birth", "Stand"])
	var point: Dictionary = _point(host, points)
	var skeleton: Skeleton3D = host.find_child("Skeleton", true, false)
	if point.is_empty() or skeleton == null:
		host.add_child(model)
		return model
	var holder: BoneAttachment3D = BoneAttachment3D.new()
	holder.bone_name = skeleton.get_bone_name(point["bone"])
	skeleton.add_child(holder)
	holder.add_child(model)
	# Attachment positions are in model space; the holder already sits on the bone's pivot.
	model.position = (point["position"] as Vector3) - skeleton.get_bone_global_rest(point["bone"]).origin
	return model


func _launch(caster: int, target: int, spell_id: int) -> void:
	var visuals: SpellVisuals = WowAssets.spell_visuals
	var speed: float = visuals.missile_speed(spell_id)
	var from: Vector3 = _point_position(caster, SpellVisuals.SLOT_POINTS["RightHandEffect"])
	if speed <= INSTANT_SPEED or from == Vector3.ZERO or _model_of(target) == null:
		_impact(target, spell_id)
		return
	var missile: Node3D = WowAssets.loader.load_m2(visuals.missile(spell_id))
	if missile == null:
		_impact(target, spell_id)
		return
	RibbonTrail.attach(missile, visuals.missile(spell_id))
	CreatureModels.mark_unit(missile)
	UnitAnimations.set_base(missile, ["Stand"])
	add_child(missile)
	missile.global_position = from
	_missiles.append({"node": missile, "target": target, "spell": spell_id, "speed": speed})


# Moves a missile a frame on, returning false once it has landed or lost its target.
func _advance(missile: Dictionary, delta: float) -> bool:
	var node: Node3D = missile["node"]
	if not is_instance_valid(node):
		return false
	var goal: Vector3 = _point_position(missile["target"], SpellVisuals.SLOT_POINTS["ChestEffect"])
	if goal == Vector3.ZERO:
		node.queue_free()
		return false
	var step: Vector3 = goal - node.global_position
	if step.length() <= missile["speed"] * delta:
		_impact(missile["target"], missile["spell"])
		node.queue_free()
		return false
	node.global_position += step.normalized() * missile["speed"] * delta
	return true


func _drop_precast(caster: int) -> void:
	_posing.erase(caster)
	for model: Node3D in _casting.get(caster, []):
		if is_instance_valid(model):
			model.queue_free()
	_casting.erase(caster)


func _clear_sparkle(guid: int) -> void:
	if _sparkles.has(guid):
		if is_instance_valid(_sparkles[guid]):
			_sparkles[guid].queue_free()
		_sparkles.erase(guid)


# The timer carries the instance id because the effect may be gone before it fires.
func _expire(model: Node3D, seconds: float) -> void:
	var id: int = model.get_instance_id()
	get_tree().create_timer(seconds).timeout.connect(
		func() -> void:
			var expired: Node3D = instance_from_id(id) as Node3D
			if expired:
				expired.queue_free()
	)


func _length(model: Node3D) -> float:
	var player: AnimationPlayer = model.get_node_or_null("AnimationPlayer")
	if player == null or player.current_animation.is_empty():
		return 0.0
	return player.get_animation(player.current_animation).length


# Where an attachment point sits in the world, or ZERO when the unit is not shown.
func _point_position(guid: int, points: Array) -> Vector3:
	var host: Node3D = _model_of(guid)
	if host == null:
		return Vector3.ZERO
	var point: Dictionary = _point(host, points)
	var skeleton: Skeleton3D = host.find_child("Skeleton", true, false)
	if point.is_empty() or skeleton == null:
		return host.global_position
	return skeleton.global_transform * (point["position"] as Vector3)


func _point(host: Node3D, points: Array) -> Dictionary:
	var path: String = host.get_meta("m2_path", "")
	if path.is_empty():
		return {}
	var carried: Dictionary[int, Dictionary] = {}
	for point: Dictionary in WowAssets.loader.get_m2_info(path).get("attachments", []):
		carried[int(point["id"])] = point
	for id: int in points:
		if carried.has(id):
			return carried[id]
	return {}


func _model_of(guid: int) -> Node3D:
	if _player and guid == WowClient.session.get_player_guid():
		return _player.model()
	return _entities.unit_node(guid) if _entities else null
