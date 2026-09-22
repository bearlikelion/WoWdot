class_name NamePlate
extends Button

const HOVER_NAME_COLOR: Color = Color(1.0, 1.0, 0.0)
const PLAYER_BAR_COLOR: Color = Color(0.0, 0.0, 1.0)

var guid: int = 0

@onready var _health: TextureProgressBar = %HealthBar
@onready var _name: Label = %Name
@onready var _level: Label = %Level


func _ready() -> void:
	mouse_entered.connect(func() -> void: _name.modulate = HOVER_NAME_COLOR)
	mouse_exited.connect(func() -> void: _name.modulate = Color.WHITE)


func update(session: WowSession, reaction: UnitReaction.Reaction) -> void:
	var player: int = session.get_player_guid()
	var level: int = session.get_field(guid, "UNIT_FIELD_LEVEL")
	_name.text = session.get_object_name(guid)
	_level.text = str(level)
	_level.modulate = UnitReaction.level_color(level, session.get_field(player, "UNIT_FIELD_LEVEL"))
	_health.value = float(session.get_field(guid, "UNIT_FIELD_HEALTH")) \
	/ maxi(session.get_field(guid, "UNIT_FIELD_MAXHEALTH"), 1)
	var is_player: bool = session.get_object_type(guid) == Entities.ObjectType.PLAYER
	_health.tint_progress = PLAYER_BAR_COLOR if is_player and \
	reaction == UnitReaction.Reaction.FRIENDLY else UnitReaction.COLORS[reaction]
