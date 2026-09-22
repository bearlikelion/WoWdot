@tool
class_name TargetOfTargetFrame
extends UnitFrame


func _ready() -> void:
	if Engine.is_editor_hint():
		super()
		return
	_name_label = %Name
	_health_bar = %HealthBar
	_power_bar = %ManaBar
	_portrait_rect = %Portrait
	# The stock frame level puts the border art and its text over the bars.
	move_child(%TextureFrame, -1)
	super()


func _update_unit() -> void:
	%DeadText.visible = WowClient.session.get_field(guid, "UNIT_FIELD_HEALTH") == 0
