class_name VideoOptionsCheck
extends Control

# Opens the video options and their resolution menu, saving user://video_options_<step>.png.
const FRAME: PackedScene = preload("res://ui/video_options_frame.tscn")

var _frame: VideoOptionsFrame


func _ready() -> void:
	_frame = FRAME.instantiate()
	add_child(_frame)
	_frame.show()
	await _shot("frame")
	var volumetric: WowButton = _frame.get_node("%VideoOptionsFrameCheckButton5")
	var shadows: WowButton = _frame.get_node("%VideoOptionsFrameCheckButton4")
	assert(volumetric.disabled != shadows.checked)
	_frame.get_node("%VideoOptionsFrameResolutionDropDownButton").pressed.emit()
	var menu: DropDownList = _frame._menu
	assert(menu.visible and not _frame._resolutions.is_empty())
	print("video_options_check resolutions %s" % [_frame._resolutions])
	await _shot("menu")
	menu.get_node("%DropDownList1Button1").pressed.emit()
	assert(not menu.visible and _frame._resolution == _frame._resolutions[0])
	await _shot("chosen")
	print("video_options_check passed")
	get_tree().quit()


func _shot(step: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://video_options_%s.png" % step)
