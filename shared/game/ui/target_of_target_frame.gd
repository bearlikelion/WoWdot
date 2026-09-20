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
	super()
