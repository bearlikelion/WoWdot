class_name World
extends Node3D

signal player_ready

# How far TargetNearestEnemy and TargetNearestFriend look, in yards.
const TAB_RANGE: float = 40.0
const UNIT_FLAG_NON_ATTACKABLE: int = 0x2
const UNIT_FLAG_NOT_SELECTABLE: int = 0x2000000
const WALKING_FLAGS: int = Player.MoveFlag.FORWARD | Player.MoveFlag.BACKWARD \
| Player.MoveFlag.STRAFE_LEFT | Player.MoveFlag.STRAFE_RIGHT
const PLAYER_FLAG_GHOST: int = 0x10
const HIDDEN_GEAR_FLAGS: int = CharacterModels.PLAYER_FLAG_HIDE_HELM \
		| CharacterModels.PLAYER_FLAG_HIDE_CLOAK
const STAND_STATE_STAND: int = 0
const STAND_STATE_SIT: int = 1
const UNIT_DYNFLAG_LOOTABLE: int = 0x1
# The golden rings the stock client plays on the player when they gain a level.
const LEVEL_UP_EFFECT: String = "Spells\\LevelUp\\LevelUp.m2"
const LEVEL_UP_SECONDS: float = 3.0
const GAMEOBJECT_TYPE_MAILBOX: int = 19
const GAMEOBJECT_TYPE_MEETING_STONE: int = 23
const NPC_FLAG_AUCTIONEER: int = 0x1000
const NPC_FLAG_STABLEMASTER: int = 0x4000
const SCREENSHOT_DIRECTORY: String = "user://Screenshots"
const SPEED_CHANGES: Dictionary[String, Player.SpeedKind] = {
	"SMSG_FORCE_WALK_SPEED_CHANGE": Player.SpeedKind.WALK,
	"SMSG_FORCE_RUN_SPEED_CHANGE": Player.SpeedKind.RUN,
	"SMSG_FORCE_RUN_BACK_SPEED_CHANGE": Player.SpeedKind.RUN_BACK,
	"SMSG_FORCE_SWIM_SPEED_CHANGE": Player.SpeedKind.SWIM,
	"SMSG_FORCE_SWIM_BACK_SPEED_CHANGE": Player.SpeedKind.SWIM_BACK,
}
const FLAG_CHANGES: Dictionary[String, Player.MoveFlag] = {
	"SMSG_FORCE_MOVE_ROOT": Player.MoveFlag.ROOT,
	"SMSG_FORCE_MOVE_UNROOT": Player.MoveFlag.ROOT,
	"SMSG_MOVE_WATER_WALK": Player.MoveFlag.WATERWALKING,
	"SMSG_MOVE_LAND_WALK": Player.MoveFlag.WATERWALKING,
	"SMSG_MOVE_FEATHER_FALL": Player.MoveFlag.SAFE_FALL,
	"SMSG_MOVE_NORMAL_FALL": Player.MoveFlag.SAFE_FALL,
	"SMSG_MOVE_SET_HOVER": Player.MoveFlag.HOVER,
	"SMSG_MOVE_UNSET_HOVER": Player.MoveFlag.HOVER,
}
const TRANSFER_ABORTS: Dictionary[int, String] = {
	1: "TRANSFER_ABORT_MAX_PLAYERS", 2: "TRANSFER_ABORT_NOT_FOUND",
	3: "TRANSFER_ABORT_TOO_MANY_INSTANCES", 5: "TRANSFER_ABORT_ZONE_IN_COMBAT",
}
const FLAGS_APPLIED: PackedStringArray = [
	"SMSG_FORCE_MOVE_ROOT", "SMSG_MOVE_WATER_WALK", "SMSG_MOVE_FEATHER_FALL", "SMSG_MOVE_SET_HOVER",
]

var _auto_attacking: bool = false
# The enemy targeted before the current target, for TargetLastEnemy.
var _last_hostile: int = 0
var _worn: PackedInt32Array = []
var _dressing: bool = false
var _mount_display: int = 0
# Which of the helm and cloak the server has hidden, and which we have asked it to.
var _hidden_gear: int = -1
var _wanted_gear: int = -1
# The player's own model, under the mount while riding, and the weapons it carries.
var _rider: Node3D
var _weapons: Array = []
var _sheath_state: ItemModels.SheathState = ItemModels.SheathState.UNARMED
var _area: int = -1
var _hovered: int = 0
var _pending_object: int = 0
var _death: Death
var _release_offered: bool = false
var _reclaim_offered: bool = false
var _ghost: bool = false

@onready var _map: WowMap = $WowMap
@onready var _player: Player = $Player
@onready var _entities: Entities = $Entities
@onready var _effects: SpellEffects = $SpellEffects
@onready var _name_plates: NamePlates = %NamePlates
@onready var _transports: Transports = $Transports
@onready var _area_triggers: AreaTriggers = $AreaTriggers
@onready var _selection: SelectionCircle = $SelectionCircle
@onready var _sun: DirectionalLight3D = $Sun
@onready var _hud: Hud = %Hud
@onready var _sky: WorldSky = $WorldSky
@onready var _weather: WorldWeather = $WorldWeather


func _ready() -> void:
	WowAssets.video.changed.connect(_apply_video)
	_apply_video()
	_player.movement_changed.connect(_on_player_movement_changed)
	_player.clicked.connect(_on_player_clicked)
	_player.interacted.connect(_on_player_interacted)
	_hud.action_used.connect(_on_action_used)
	_hud.spell_used.connect(_use_spell)
	_hud.unit_selected.connect(select)
	_name_plates.unit_clicked.connect(select)
	_hud.ticket_requested.connect(func(text: String) -> void:
		var here: Vector3 = WowCoords.from_godot(_player.global_position)
		ServerNotices.open_ticket(text, _sky.map_id, here)
	)
	WowClient.session.attack_started.connect(_on_attack_changed.bind(true))
	WowClient.session.attack_stopped.connect(_on_attack_changed.bind(false))
	WowClient.session.melee_swing.connect(_on_melee_swing)
	WowClient.session.object_updated.connect(_on_object_updated)
	WowClient.session.item_info_received.connect(_on_item_info_received)
	WowClient.session.object_created.connect(_on_object_created)
	WowClient.session.player_teleported.connect(_on_player_teleported)
	WowClient.session.object_moved.connect(_on_object_moved)
	WowClient.session.packet_received.connect(_on_packet_received)
	WowClient.session.transfer_aborted.connect(_on_transfer_aborted)
	WowClient.session.leveled_up.connect(_on_leveled_up)
	WowClient.session.game_object_info_received.connect(_on_game_object_info_received)
	_effects.watch(_entities, _player)
	_transports.watch(_entities)
	_area_triggers.watch(_player)
	UnitVoice.map = _map
	WowAssets.interface.changed.connect(_on_interface_changed)
	_death = Death.new(WowClient.session)
	_death.corpse_located.connect(_hud.show_corpse)
	_death.resurrect_offered.connect(_on_resurrect_offered)
	_death.spirit_healer_offered.connect(_on_spirit_healer_offered)


func _process(_delta: float) -> void:
	if not _player.active and _map.is_ground_ready(_player.global_position):
		_player.active = true
		player_ready.emit()
	var wow_position: Vector3 = WowCoords.from_godot(_player.global_position)
	_hud.show_location(_map.map_name, wow_position, _player.orientation())
	_sky.wow_position = wow_position
	_player.set_water_surface(_map.liquid_height_at(_player.global_position))
	var eye: Vector3 = get_viewport().get_camera_3d().global_position
	_sky.underwater = eye.y < _map.liquid_height_at(eye)
	_weather.visible = not _sky.underwater
	_offer_reclaim()
	var area: int = _map.area_id_at(_player.global_position)
	if area != 0 and area != _area:
		_area = area
		var session: WowSession = WowClient.session
		var race: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_BYTES_0") & 0xFF
		_hud.show_area(area, race)
		WowAssets.audio.play_zone(area)
		var zone: int = AreaInfo.zone_of(area)
		Channels.enter_zone(AreaInfo.area_name(zone), AreaInfo.flags(zone))


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
	elif _exact(event, "toggle_sheath"):
		var drawn: bool = _sheath_state != ItemModels.SheathState.UNARMED
		_sheathe(ItemModels.SheathState.UNARMED if drawn else ItemModels.SheathState.MELEE)
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
	_sky.map_id = map_id
	_transports.map_id = map_id
	_area_triggers.map_id = map_id
	_player.place(WowCoords.to_godot(wow_position), orientation)
	var guid: int = WowClient.session.get_player_guid()
	if WowClient.session.has_object(guid):
		_on_object_created(guid, WowClient.session.get_object_type(guid))


# Physics stops until the new map's ground is under the player again.
func begin_transfer() -> void:
	_player.active = false


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
	_selection.target = guid
	_name_plates.target = guid


func _on_player_movement_changed(
	opcode: String, godot_position: Vector3, orientation: float, flags: int,
	fall_time_msec: int, jump_velocity: Vector3, ack_counter: int, ack_tail: PackedByteArray,
) -> void:
	if flags & WALKING_FLAGS:
		WowClient.tutorials.moved()
	WowClient.session.send_movement(
		opcode, WowCoords.from_godot(godot_position), orientation, flags,
		fall_time_msec, WowCoords.from_godot(jump_velocity), _player.pitch(),
		ack_counter, ack_tail, _player.transport_guid(),
		WowCoords.from_godot(_player.transport_offset()), _player.transport_orientation(),
	)


# Corpses are only offered once each, so a refused popup stays closed until the state changes.
func _follow_death(dead: bool, ghost: bool) -> void:
	if not dead and not ghost:
		_ghost = false
		_release_offered = false
		_reclaim_offered = false
		_death.forget_corpse()
		_hud.show_corpse(Vector3.ZERO, -1)
		return
	_ghost = ghost
	if not ghost and not _release_offered:
		_release_offered = true
		var revive: Callable = _death.self_resurrect if _death.can_self_resurrect() else Callable()
		_hud.ask_release(_death.release, revive)


func _offer_reclaim() -> void:
	if not _ghost or _reclaim_offered:
		return
	if _death.corpse_map < 0:
		return _death.query_corpse()
	if not _death.may_reclaim():
		return
	var corpse: Vector3 = WowCoords.to_godot(_death.corpse_position)
	if corpse.distance_to(_player.global_position) > Death.RECLAIM_RANGE:
		return
	if _death.corpse_guid() == 0:
		return
	_reclaim_offered = true
	_hud.ask_reclaim(_death.reclaim)


func _on_resurrect_offered(caster_name: String, _sickness: bool) -> void:
	_hud.ask_resurrect(caster_name, _death.answer_resurrect)


func _on_spirit_healer_offered(healer_guid: int) -> void:
	_hud.ask_spirit_healer(_death.activate_spirit_healer.bind(healer_guid))


func _play_emote(payload: PackedByteArray) -> void:
	var reader: PacketReader = PacketReader.new(payload)
	var clip: String = Emotes.animation(reader.u32())
	var guid: int = reader.u64()
	if clip.is_empty():
		return
	if guid == WowClient.session.get_player_guid():
		_player.play_once([clip])
		return
	var node: Node3D = _entities.unit_node(guid)
	if node:
		UnitAnimations.play_once(node, [clip])


func _on_transfer_aborted(reason: int) -> void:
	_hud.show_error(WowStrings.get_text(TRANSFER_ABORTS.get(reason, ""), "Transfer aborted"))


# Server changes to the player's own movement, which the client applies and acknowledges.
func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode == "SMSG_EMOTE":
		return _play_emote(payload)
	var knock_back: bool = opcode == "SMSG_MOVE_KNOCK_BACK"
	if not (knock_back or SPEED_CHANGES.has(opcode) or FLAG_CHANGES.has(opcode)):
		return
	var reader: PacketReader = PacketReader.new(payload)
	if reader.packed_guid() != WowClient.session.get_player_guid():
		return
	var counter: int = reader.u32()
	if SPEED_CHANGES.has(opcode):
		_player.force_speed(SPEED_CHANGES[opcode], reader.f32(), counter)
	elif FLAG_CHANGES.has(opcode):
		_player.force_flag(FLAG_CHANGES[opcode], opcode in FLAGS_APPLIED, counter)
	else:
		var cos_angle: float = reader.f32()
		var sin_angle: float = reader.f32()
		var xy_speed: float = reader.f32()
		var z_speed: float = reader.f32()
		var wow_velocity: Vector3 = Vector3(cos_angle * xy_speed, sin_angle * xy_speed, z_speed)
		_player.knock_back(WowCoords.to_godot(wow_velocity), counter)


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
		if WowAssets.spells.uses_ranged_slot(spell):
			_sheathe(ItemModels.SheathState.RANGED)
		var target: int = 0 if WowAssets.spells.targets_caster(spell) else _hud.target()
		_face(target)
		session.cast_spell(spell, target)
	elif _auto_attacking:
		session.stop_attack()
	elif _hud.target() != 0:
		_face(_hud.target())
		session.attack(_hud.target())


# The stock client turns you at whatever you aim at, so nothing is ever cast behind your back.
func _face(guid: int) -> void:
	var node: Node3D = _entities.unit_node(guid) if guid != 0 else null
	if node:
		_player.face(node.global_position)


# PLAYER_LEVEL_UP: the chime, the notice over the screen and the gains in the chat.
func _on_leveled_up(level: int, health: int, mana: int, stats: PackedInt32Array) -> void:
	WowAssets.audio.play_sound("LEVELUP")
	_effects.flourish(WowClient.session.get_player_guid(), LEVEL_UP_EFFECT, LEVEL_UP_SECONDS)
	_hud.show_notice(WowStrings.get_text("LEVEL_UP") % level)
	var lines: PackedStringArray = []
	if health > 0 and mana > 0:
		lines.append(WowStrings.get_text("LEVEL_UP_HEALTH_MANA") % [health, mana])
	elif health > 0:
		lines.append(WowStrings.get_text("LEVEL_UP_HEALTH") % health)
	for stat: int in stats.size():
		if stats[stat] > 0:
			lines.append(WowStrings.get_text("LEVEL_UP_STAT") % [
				WowStrings.get_text("SPELL_STAT%d_NAME" % (stat + 1)), stats[stat],
			])
	for line: String in lines:
		_hud.add_system_line(line)


func _on_attack_changed(attacker: int, _victim: int, attacking: bool) -> void:
	if attacker == WowClient.session.get_player_guid():
		_auto_attacking = attacking
		_player.in_combat = attacking
		if attacking:
			_sheathe(ItemModels.SheathState.MELEE)


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
	var dead: bool = session.get_field(guid, "UNIT_FIELD_HEALTH") == 0
	var ghost: bool = (session.get_field(guid, "PLAYER_FLAGS") & PLAYER_FLAG_GHOST) != 0
	_player.set_dead(dead)
	_sky.dead = dead or ghost
	_follow_death(dead, ghost)
	_player.stand_state = session.get_field(guid, "UNIT_FIELD_BYTES_1") & 0xFF
	var mount: int = session.get_field(guid, "UNIT_FIELD_MOUNTDISPLAYID")
	var gear_changed: bool = _read_hidden_gear()
	if gear_changed or CharacterModels.visible_items(session, guid) != _worn \
	or mount != _mount_display:
		_dress_player()
	elif _rider and ItemModels.sheath_state(session, guid) != _sheath_state:
		_sheath_state = ItemModels.sheath_state(session, guid)
		var model_path: String = WowAssets.creatures.model_path(
			session.get_field(guid, "UNIT_FIELD_DISPLAYID")
		)
		WowAssets.characters.item_models.arm(_rider, model_path, _weapons, _sheath_state)


func _on_item_info_received(_entry: int) -> void:
	if _dressing:
		_dress_player()


func _dress_player() -> void:
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	var look: Dictionary = CharacterModels.player_look(session, guid)
	_worn = CharacterModels.visible_items(session, guid)
	_dressing = look["pending"]
	_weapons = look["weapons"]
	_sheath_state = look["sheath_state"]
	var display: int = session.get_field(guid, "UNIT_FIELD_DISPLAYID")
	var model: Node3D = WowAssets.creatures.instantiate(display, look)
	_rider = model
	_mount_display = session.get_field(guid, "UNIT_FIELD_MOUNTDISPLAYID")
	var mount: Node3D = WowAssets.creatures.instantiate(_mount_display) if _mount_display else null
	if model and mount:
		_seat(mount, model)
		model = mount
	if model:
		_player.set_model(model)
		UnitVoice.attach(model, guid, display, _mount_display)
		_entities.add_nameplate(guid, model)


# Show Helm and Show Cloak live in the character's own PLAYER_FLAGS, so the server's word sets them.
func _read_hidden_gear() -> bool:
	var session: WowSession = WowClient.session
	var hidden: int = session.get_field(session.get_player_guid(), "PLAYER_FLAGS") \
			& HIDDEN_GEAR_FLAGS
	if hidden == _hidden_gear:
		return false
	_hidden_gear = hidden
	_wanted_gear = hidden
	var settings: InterfaceSettings = WowAssets.interface
	settings.set_on(&"show_helm", (hidden & CharacterModels.PLAYER_FLAG_HIDE_HELM) == 0)
	settings.set_on(&"show_cloak", (hidden & CharacterModels.PLAYER_FLAG_HIDE_CLOAK) == 0)
	return true


# CMSG_SHOWING_HELM and CMSG_SHOWING_CLOAK carry nothing and toggle the flag they are named for.
func _on_interface_changed() -> void:
	if _wanted_gear < 0:
		return
	var settings: InterfaceSettings = WowAssets.interface
	var wanted: int = 0
	if not settings.is_on(&"show_helm"):
		wanted |= CharacterModels.PLAYER_FLAG_HIDE_HELM
	if not settings.is_on(&"show_cloak"):
		wanted |= CharacterModels.PLAYER_FLAG_HIDE_CLOAK
	var turned: int = wanted ^ _wanted_gear
	_wanted_gear = wanted
	if turned & CharacterModels.PLAYER_FLAG_HIDE_HELM:
		WowClient.session.send_packet("CMSG_SHOWING_HELM", PackedByteArray())
	if turned & CharacterModels.PLAYER_FLAG_HIDE_CLOAK:
		WowClient.session.send_packet("CMSG_SHOWING_CLOAK", PackedByteArray())


func _apply_video() -> void:
	_sun.shadow_enabled = WowAssets.video.shadows


# CMSG_SETSHEATHED; the server's UNIT_FIELD_BYTES_2 update moves the weapons.
func _sheathe(state: ItemModels.SheathState) -> void:
	if state == _sheath_state:
		return
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_u32(0, state)
	WowClient.session.send_packet("CMSG_SETSHEATHED", payload)


# A mounted rider sits on the mount's first attachment, the saddle, playing Mount.
func _seat(mount: Node3D, rider: Node3D) -> void:
	var path: String = WowAssets.creatures.model_path(_mount_display)
	var seat: Vector3 = Vector3.ZERO
	for attachment: Dictionary in WowAssets.loader.get_m2_info(path).get("attachments", []):
		if attachment["id"] == 0:
			seat = attachment["position"]
	mount.add_child(rider)
	rider.position = seat
	rider.scale = rider.scale / mount.scale
	# The animation only takes once the mount, and so the rider, is in the tree.
	UnitAnimations.set_base.call_deferred(rider, PackedStringArray(["Mount"]))


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


# Right-clicking a unit targets it, then talks to it or, when it is an enemy, attacks it.
func _on_player_interacted(screen_position: Vector2) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var from: Vector3 = camera.project_ray_origin(screen_position)
	var guid: int = _entities.pick(from, camera.project_ray_normal(screen_position))
	if guid == 0:
		return
	select(guid)
	var session: WowSession = WowClient.session
	if _is_lootable(guid):
		LootFrame.loot(guid)
		return
	if session.get_object_type(guid) == Entities.ObjectType.GAMEOBJECT:
		_use_game_object(guid)
		return
	if session.get_field(guid, "UNIT_NPC_FLAGS") & NPC_FLAG_AUCTIONEER:
		_hud.open_auction_house(guid)
		return
	if session.get_field(guid, "UNIT_NPC_FLAGS") & NPC_FLAG_STABLEMASTER:
		_hud.open_stable(guid)
		return
	if NpcDialog.interact(guid):
		UnitVoice.speak(guid, UnitVoice.Speech.GREETING)
		return
	var me: int = session.get_player_guid()
	var hostile: bool = UnitReaction.between(session, me, guid) == UnitReaction.Reaction.HOSTILE
	if hostile and not _auto_attacking:
		_face(guid)
		session.attack(guid)


# A game object's type comes from a query, so the first click on one waits for the answer.
func _use_game_object(guid: int) -> void:
	var session: WowSession = WowClient.session
	var info: Dictionary = session.get_game_object_info(
		session.get_field(guid, "OBJECT_FIELD_ENTRY")
	)
	if info.is_empty():
		_pending_object = guid
		return
	if info.get("type", 0) == GAMEOBJECT_TYPE_MAILBOX:
		_hud.open_mailbox(guid)
		return
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, guid)
	if info.get("type", 0) == GAMEOBJECT_TYPE_MEETING_STONE:
		# A second click on a stone leaves the queue the first one joined.
		if ServerNotices.meeting_stone_area != 0:
			session.send_packet("CMSG_MEETINGSTONE_LEAVE", PackedByteArray())
		else:
			session.send_packet("CMSG_MEETINGSTONE_JOIN", payload)
		return
	session.send_packet("CMSG_GAMEOBJ_USE", payload)


func _on_game_object_info_received(entry: int) -> void:
	var session: WowSession = WowClient.session
	if _pending_object == 0 or session.get_field(_pending_object, "OBJECT_FIELD_ENTRY") != entry:
		return
	var guid: int = _pending_object
	_pending_object = 0
	_use_game_object(guid)


func _is_lootable(guid: int) -> bool:
	var session: WowSession = WowClient.session
	return session.get_field(guid, "UNIT_FIELD_HEALTH") == 0 \
	and session.get_field(guid, "UNIT_DYNAMIC_FLAGS") & UNIT_DYNFLAG_LOOTABLE != 0


func _on_object_moved(guid: int, movement: Dictionary) -> void:
	if guid == WowClient.session.get_player_guid() and movement.has("points"):
		_follow_server_path()


# Flights, including one the server resumes because the character logged out on it.
func _follow_server_path() -> void:
	var path: Dictionary = WowClient.session.get_player_path()
	if path.is_empty():
		return
	var points: PackedVector3Array = []
	for point: Vector3 in path["points"]:
		points.append(WowCoords.to_godot(point))
	_player.follow_path(points, path["duration_msec"], path["elapsed_msec"], path["from_start"])


func _on_player_teleported(wow_position: Vector3, orientation: float) -> void:
	_player.place(WowCoords.to_godot(wow_position), orientation)
	_area_triggers.settle()


func _on_object_created(guid: int, _type_id: int) -> void:
	if guid != WowClient.session.get_player_guid():
		return
	_hud.show_player(guid)
	_player.set_speeds(WowClient.session.get_object_speeds(guid))
	_read_hidden_gear()
	_dress_player()
	_follow_server_path()
