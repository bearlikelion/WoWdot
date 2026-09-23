class_name NamePlates
extends Control

signal unit_clicked(guid: int)

const PLATE: PackedScene = preload("res://ui/name_plate.tscn")
const SETTINGS_PATH: String = "user://interface.cfg"
const SECTION: String = "name_plates"
const UNIT_FLAG_NOT_SELECTABLE: int = 0x2000000
const MAX_DISTANCE: float = 40.0
# The plate hangs from a point this far over the unit's head.
const HEAD_LIFT: float = 2.0 / 3.0
# The stock plate is a tenth of the screen's diagonal wide, whatever the UI scale.
const WIDTH_OF_DIAGONAL: float = 0.1
const PLATE_WIDTH: float = 128.0
# With a target, every other plate fades to this.
const DIM_ALPHA: float = 178.0 / 255.0

@export var entities: Entities
@export var player: Player

# Both start off, as the stock client does until V or Shift+V is pressed.
var show_enemies: bool = false
var show_friends: bool = false
var target: int = 0

var _plates: Dictionary[int, NamePlate] = {}


func _ready() -> void:
	var saved: ConfigFile = ConfigFile.new()
	if saved.load(SETTINGS_PATH) == OK:
		show_enemies = saved.get_value(SECTION, "enemies", false)
		show_friends = saved.get_value(SECTION, "friends", false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("name_plates", false, true):
		show_enemies = not show_enemies
	elif event.is_action_pressed("friendly_name_plates", false, true):
		show_friends = not show_friends
	else:
		return
	get_viewport().set_input_as_handled()
	_save()


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var session: WowSession = WowClient.session
	var live: Dictionary[int, bool] = {}
	if camera and (show_enemies or show_friends):
		var plate_scale: float = size.length() * WIDTH_OF_DIAGONAL / PLATE_WIDTH
		for guid: int in entities.shown_guids():
			var at: Vector2 = _plate_point(camera, session, guid)
			if at == Vector2.INF:
				continue
			live[guid] = true
			var plate: NamePlate = _plates.get(guid)
			if plate == null:
				plate = _add_plate(guid)
			plate.update(session, UnitReaction.between(session, session.get_player_guid(), guid))
			plate.scale = Vector2(plate_scale, plate_scale)
			plate.position = at - Vector2(PLATE_WIDTH * 0.5, 0.0)
			plate.modulate.a = DIM_ALPHA if target != 0 and guid != target else 1.0
	for guid: int in _plates.keys():
		if not live.has(guid):
			_plates[guid].queue_free()
			_plates.erase(guid)
			entities.set_plated(guid, false)


# Where the plate's top centre goes on screen, or INF for a unit that gets no plate.
func _plate_point(camera: Camera3D, session: WowSession, guid: int) -> Vector2:
	if not session.has_object(guid) \
	or session.get_object_type(guid) == Entities.ObjectType.GAMEOBJECT \
	or session.get_field(guid, "UNIT_FIELD_FLAGS") & UNIT_FLAG_NOT_SELECTABLE \
	or session.get_field(guid, "UNIT_FIELD_HEALTH") <= 0:
		return Vector2.INF
	var friendly: bool = UnitReaction.between(session, session.get_player_guid(), guid) \
	== UnitReaction.Reaction.FRIENDLY
	if not (show_friends if friendly else show_enemies):
		return Vector2.INF
	var head: Vector3 = entities.head_position(guid)
	if head == Vector3.ZERO or head.distance_to(player.global_position) > MAX_DISTANCE:
		return Vector2.INF
	head += Vector3.UP * HEAD_LIFT
	if camera.is_position_behind(head) or not camera.is_position_in_frustum(head):
		return Vector2.INF
	return camera.unproject_position(head)


func _add_plate(guid: int) -> NamePlate:
	var plate: NamePlate = PLATE.instantiate()
	plate.guid = guid
	add_child(plate)
	plate.pressed.connect(unit_clicked.emit.bind(guid))
	_plates[guid] = plate
	entities.set_plated(guid, true)
	return plate


func _save() -> void:
	var saved: ConfigFile = ConfigFile.new()
	saved.load(SETTINGS_PATH)
	saved.set_value(SECTION, "enemies", show_enemies)
	saved.set_value(SECTION, "friends", show_friends)
	saved.save(SETTINGS_PATH)
