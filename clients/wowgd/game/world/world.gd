class_name World
extends Node3D

signal player_ready

# How far TargetNearestEnemy and TargetNearestFriend look, in yards.
const TAB_RANGE: float = 40.0
const UNIT_FLAG_NON_ATTACKABLE: int = 0x2
const UNIT_FLAG_NOT_SELECTABLE: int = 0x2000000
const STAND_STATE_STAND: int = 0
const STAND_STATE_SIT: int = 1
const SCREENSHOT_DIRECTORY: String = "user://Screenshots"

var _auto_attacking: bool = false
# The enemy targeted before the current target, for TargetLastEnemy.
var _last_hostile: int = 0
var _worn: PackedInt32Array = []
var _dressing: bool = false
var _area: int = -1
var _hovered: int = 0

@onready var _map: WowMap = $WowMap
@onready var _player: Player = $Player
@onready var _entities: Entities = $Entities
@onready var _hud: Hud = %Hud


func _ready() -> void:
	_player.movement_changed.connect(_on_player_movement_changed)
	_player.clicked.connect(_on_player_clicked)
	_hud.action_used.connect(_on_action_used)
	_hud.spell_used.connect(_use_spell)
	_hud.unit_selected.connect(select)
	WowClient.session.attack_started.connect(_on_attack_changed.bind(true))
	WowClient.session.attack_stopped.connect(_on_attack_changed.bind(false))
	WowClient.session.melee_swing.connect(_on_melee_swing)
	WowClient.session.object_updated.connect(_on_object_updated)
	WowClient.session.item_info_received.connect(_on_item_info_received)
	WowClient.session.object_created.connect(_on_object_created)


func _process(_delta: float) -> void:
	if not _player.active and _map.is_ground_ready(_player.global_position):
		_player.active = true
		player_ready.emit()
	var wow_position: Vector3 = WowCoords.from_godot(_player.global_position)
	_hud.show_location(_map.map_name, wow_position, _player.orientation())
	var area: int = _map.area_id_at(_player.global_position)
	if area != 0 and area != _area:
		_area = area
		var session: WowSession = WowClient.session
		var race: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_BYTES_0") & 0xFF
		_hud.show_area(area, race)


func _unhandled_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion and motion.button_mask == 0:
		_update_hover(motion.position)
	if _binding_pressed(event):
		get_viewport().set_input_as_handled()


# The Bindings.xml actions the world answers; true when the event was one of them.
func _binding_pressed(event: InputEvent) -> bool:
	var typing: bool = get_viewport().gui_get_focus_owner() is LineEdit
	if not event.is_pressed() or event.is_echo() or typing:
		return false
	var session: WowSession = WowClient.session
	var target: int = _hud.target()
	if _exact(event, "target_nearest_enemy"):
		_cycle_target(false, 1)
	elif _exact(event, "target_previous_enemy"):
		_cycle_target(false, -1)
	elif _exact(event, "target_nearest_friend"):
		_cycle_target(true, 1)
	elif _exact(event, "target_previous_friend"):
		_cycle_target(true, -1)
	elif _exact(event, "target_self"):
		select(session.get_player_guid())
	elif _exact(event, "target_last_hostile"):
		if session.has_object(_last_hostile):
			select(_last_hostile)
	elif _exact(event, "assist_target"):
		var assisted: int = _unit_guid(target, "UNIT_FIELD_TARGET")
		if target != 0 and session.has_object(assisted):
			select(assisted)
	elif _exact(event, "attack_target"):
		if target == 0:
			_hud.show_error(WowStrings.get_text("ERR_GENERIC_NO_TARGET"))
		elif not _auto_attacking:
			session.attack(target)
	elif _exact(event, "sit_stand"):
		var bytes_1: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_BYTES_1")
		var sitting: bool = bytes_1 & 0xFF != STAND_STATE_STAND
		var payload: PackedByteArray = []
		payload.resize(4)
		payload.encode_u32(0, STAND_STATE_STAND if sitting else STAND_STATE_SIT)
		session.send_packet("CMSG_STANDSTATECHANGE", payload)
	elif _exact(event, "toggle_ui"):
		_hud.visible = not _hud.visible
	elif _exact(event, "screenshot"):
		_save_screenshot()
	else:
		return false
	return true


func _exact(event: InputEvent, action: String) -> bool:
	return event.is_action_pressed(action, false, true)


# TargetNearestEnemy: attackable units on screen, nearest first; pressing again steps to the next.
func _cycle_target(friendly: bool, step: int) -> void:
	var session: WowSession = WowClient.session
	var player_guid: int = session.get_player_guid()
	var camera: Camera3D = get_viewport().get_camera_3d()
	var candidates: Array[int] = []
	for guid: int in _entities.visible_units(_player.global_position, TAB_RANGE, camera):
		if guid == player_guid:
			continue
		var reaction: UnitReaction.Reaction = UnitReaction.between(session, player_guid, guid)
		var flags: int = session.get_field(guid, "UNIT_FIELD_FLAGS")
		if flags & UNIT_FLAG_NOT_SELECTABLE:
			continue
		if friendly and reaction == UnitReaction.Reaction.FRIENDLY:
			candidates.append(guid)
		elif not friendly and reaction != UnitReaction.Reaction.FRIENDLY \
		and flags & UNIT_FLAG_NON_ATTACKABLE == 0 \
		and session.get_field(guid, "UNIT_FIELD_HEALTH") > 0:
			candidates.append(guid)
	if candidates.is_empty():
		return
	var index: int = candidates.find(_hud.target())
	if index < 0:
		select(candidates[0] if step > 0 else candidates[candidates.size() - 1])
	else:
		select(candidates[posmod(index + step, candidates.size())])


func _unit_guid(guid: int, field: String) -> int:
	var session: WowSession = WowClient.session
	var index: int = session.field_index(field)
	return session.get_field(guid, index) | (session.get_field(guid, index + 1) << 32)


func _save_screenshot() -> void:
	DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIRECTORY)
	var stamp: Dictionary = Time.get_datetime_dict_from_system()
	var file: String = "WoWScrnShot_%02d%02d%02d_%02d%02d%02d.png" % [
		stamp["month"], stamp["day"], stamp["year"] % 100, stamp["hour"], stamp["minute"],
		stamp["second"],
	]
	var saved: bool = get_viewport().get_texture().get_image().save_png(
		SCREENSHOT_DIRECTORY.path_join(file)
	) == OK
	_hud.show_notice(WowStrings.get_text("SCREENSHOT_SUCCESS" if saved else "SCREENSHOT_FAILURE"))


func enter(map_id: int, wow_position: Vector3, orientation: float) -> void:
	_player.active = false
	_map.map_name = WowClient.map_name(map_id)
	_player.place(WowCoords.to_godot(wow_position), orientation)
	var guid: int = WowClient.session.get_player_guid()
	if WowClient.session.has_object(guid):
		_on_object_created(guid, WowClient.session.get_object_type(guid))


func load_progress() -> float:
	return _map.load_progress(_player.global_position)


func player() -> Player:
	return _player


func hud() -> Hud:
	return _hud


func select(guid: int) -> void:
	var previous: int = _hud.target()
	var session: WowSession = WowClient.session
	if previous != 0 and previous != guid and session.has_object(previous) \
	and UnitReaction.between(session, session.get_player_guid(), previous) \
	!= UnitReaction.Reaction.FRIENDLY:
		_last_hostile = previous
	WowClient.session.set_selection(guid)
	_hud.show_target(guid)


func _on_player_movement_changed(
	opcode: String, godot_position: Vector3, orientation: float, flags: int,
	fall_time_msec: int, jump_velocity: Vector3,
) -> void:
	WowClient.session.send_movement(
		opcode, WowCoords.from_godot(godot_position), orientation, flags,
		fall_time_msec, WowCoords.from_godot(jump_velocity),
	)


func _on_action_used(slot: int) -> void:
	var session: WowSession = WowClient.session
	var buttons: PackedInt32Array = session.get_action_buttons()
	if slot < 0 or slot >= buttons.size() or buttons[slot] == 0:
		return
	var packed: int = buttons[slot]
	# ponytail: macro actions do nothing until the macro frame exists.
	match (packed >> 24) & 0xFF:
		ActionButton.ActionType.SPELL:
			_use_spell(packed & ActionButton.ACTION_MASK)
		ActionButton.ActionType.ITEM:
			var found: Vector2i = Inventory.find_item(packed & ActionButton.ACTION_MASK)
			if found.x >= 0:
				_hud.use_container_item(found.x, found.y)


# Attack toggles auto-attack on the target; every other spell is cast at it.
func _use_spell(spell: int) -> void:
	var session: WowSession = WowClient.session
	if spell != ActionButton.SPELL_ATTACK:
		session.cast_spell(spell, _hud.target())
	elif _auto_attacking:
		session.stop_attack()
	elif _hud.target() != 0:
		session.attack(_hud.target())


func _on_attack_changed(attacker: int, _victim: int, attacking: bool) -> void:
	if attacker == WowClient.session.get_player_guid():
		_auto_attacking = attacking
		_player.in_combat = attacking


func _on_melee_swing(
	attacker: int, victim: int, damage: int, _hit_info: int, victim_state: int,
) -> void:
	var guid: int = WowClient.session.get_player_guid()
	if attacker == guid:
		_player.play_once(UnitAnimations.ATTACK)
	elif victim == guid and damage > 0 and victim_state == Entities.VICTIM_STATE_HIT:
		_player.play_once(UnitAnimations.WOUND)


func _on_object_updated(guid: int) -> void:
	var session: WowSession = WowClient.session
	if guid != session.get_player_guid():
		return
	_player.set_dead(session.get_field(guid, "UNIT_FIELD_HEALTH") == 0)
	_player.stand_state = session.get_field(guid, "UNIT_FIELD_BYTES_1") & 0xFF
	if CharacterModels.visible_items(session, guid) != _worn:
		_dress_player()


func _on_item_info_received(_entry: int) -> void:
	if _dressing:
		_dress_player()


func _dress_player() -> void:
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	var look: Dictionary = CharacterModels.player_look(session, guid)
	_worn = CharacterModels.visible_items(session, guid)
	_dressing = look["pending"]
	var display: int = session.get_field(guid, "UNIT_FIELD_DISPLAYID")
	var model: Node3D = WowAssets.creatures.instantiate(display, look)
	if model:
		_player.set_model(model)


# Units under the cursor get the default-anchored unit tooltip, like the stock mouseover.
func _update_hover(screen_position: Vector2) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var from: Vector3 = camera.project_ray_origin(screen_position)
	var guid: int = _entities.pick(from, camera.project_ray_normal(screen_position))
	if guid == _hovered or GameTooltip.current == null:
		return
	_hovered = guid
	if guid != 0:
		GameTooltip.current.set_unit(self, guid)
	else:
		GameTooltip.current.hide_for(self)


func _on_player_clicked(screen_position: Vector2) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var from: Vector3 = camera.project_ray_origin(screen_position)
	var guid: int = _entities.pick(from, camera.project_ray_normal(screen_position))
	if guid != 0:
		select(guid)


func _on_object_created(guid: int, _type_id: int) -> void:
	if guid != WowClient.session.get_player_guid():
		return
	_hud.show_player(guid)
	_dress_player()
