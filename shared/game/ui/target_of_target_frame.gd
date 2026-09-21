@tool
class_name TargetOfTargetFrame
extends UnitFrame


func _ready() -> void:
	if Engine.is_editor_hint():
		super()
		return
	_name_label = %TargetofTargetName
	_health_bar = %TargetofTargetHealthBar
	_power_bar = %TargetofTargetManaBar
	_portrait_rect = %TargetofTargetPortrait
	# The stock frame level puts the border art and its text over the bars.
	move_child(%TargetofTargetTextureFrame, -1)
	super()


func _update_unit() -> void:
	%TargetofTargetDeadText.visible = WowClient.session.get_field(guid, "UNIT_FIELD_HEALTH") == 0
