class_name OptionsCategoryList
extends RefCounted


# OptionsList_OnLoad and OptionsListButton_OnClick: a button per panel that shows it alone.
static func bind(frame: Control, list: String, panels: Dictionary[String, String]) -> void:
	var buttons: Array[WowButton] = []
	while frame.has_node("%%%sButton%d" % [list, buttons.size() + 1]):
		buttons.append(frame.get_node("%%%sButton%d" % [list, buttons.size() + 1]))
	var panel_names: Array[String] = panels.keys()
	for i: int in buttons.size():
		buttons[i].visible = i < panel_names.size()
		if buttons[i].visible:
			(frame.get_node("%" + buttons[i].name + "Text") as Label).text = \
					WowStrings.get_text(panels[panel_names[i]])
			buttons[i].pressed.connect(_select.bind(frame, buttons, panel_names, i))
	_select(frame, buttons, panel_names, 0)


static func _select(
	frame: Control, buttons: Array[WowButton], panel_names: Array[String], chosen: int
) -> void:
	for i: int in panel_names.size():
		buttons[i].highlight_locked = i == chosen
		(frame.get_node("%" + panel_names[i]) as Control).visible = i == chosen
