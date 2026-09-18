class_name World
extends Node3D

signal player_ready

@onready var _map: WowMap = $WowMap
@onready var _player: Player = $Player
@onready var _entities: Entities = $Entities
@onready var _hud: Hud = %Hud


func _ready() -> void:
	_player.movement_changed.connect(_on_player_movement_changed)
	_player.clicked.connect(_on_player_clicked)
	WowClient.session.object_created.connect(_on_object_created)


func _process(_delta: float) -> void:
	if not _player.active and _map.is_ground_ready(_player.global_position):
		_player.active = true
		player_ready.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _hud.target() != 0:
		get_viewport().set_input_as_handled()
		select(0)


func enter(map_id: int, wow_position: Vector3, orientation: float) -> void:
	_player.active = false
	_map.map_name = WowClient.map_name(map_id)
	_player.place(WowCoords.to_godot(wow_position), orientation)
	var guid: int = WowClient.session.get_player_guid()
	if WowClient.session.has_object(guid):
		_on_object_created(guid, WowClient.session.get_object_type(guid))


func player() -> Player:
	return _player


func hud() -> Hud:
	return _hud


func select(guid: int) -> void:
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
	var display: int = WowClient.session.get_field(guid, "UNIT_FIELD_DISPLAYID")
	var look: Dictionary = CharacterModels.player_look(WowClient.session, guid)
	var model: Node3D = WowAssets.creatures.instantiate(display, look)
	if model:
		_player.set_model(model)
