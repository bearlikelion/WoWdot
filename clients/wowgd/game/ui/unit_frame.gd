class_name UnitFrame
extends PanelContainer

var guid: int = 0

@onready var _name: Label = %Name
@onready var _level: Label = %Level
@onready var _health: ProgressBar = %Health
@onready var _health_text: Label = %HealthText


func _ready() -> void:
	var session: WowSession = WowClient.session
	session.object_updated.connect(_on_object_updated)
	session.name_received.connect(_on_name_received)
	session.objects_destroyed.connect(_on_objects_destroyed)


# A guid of 0, or one the session no longer knows, hides the frame.
func show_unit(unit: int) -> void:
	guid = unit
	visible = guid != 0 and WowClient.session.has_object(guid)
	if visible:
		_name.text = WowClient.session.get_object_name(guid)
		_refresh()


func _refresh() -> void:
	var session: WowSession = WowClient.session
	var health: int = session.get_field(guid, "UNIT_FIELD_HEALTH")
	var max_health: int = maxi(session.get_field(guid, "UNIT_FIELD_MAXHEALTH"), 1)
	_level.text = str(session.get_field(guid, "UNIT_FIELD_LEVEL"))
	_health.max_value = max_health
	_health.value = health
	_health_text.text = "%d / %d" % [health, max_health]


func _on_object_updated(unit: int) -> void:
	if visible and unit == guid:
		_refresh()


func _on_name_received(unit: int, unit_name: String) -> void:
	if unit == guid:
		_name.text = unit_name


func _on_objects_destroyed(guids: PackedInt64Array) -> void:
	if guids.has(guid):
		show_unit(0)
