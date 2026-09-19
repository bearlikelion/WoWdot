class_name MultiActionBar
extends RefCounted

const BUTTONS: int = 12


# Gives a bar's twelve ActionButtons their slots and forwards their use; slots start at first_slot.
static func bind(bar: Control, first_slot: int, on_used: Callable) -> Array[ActionButton]:
	var buttons: Array[ActionButton] = []
	for i: int in BUTTONS:
		var button: ActionButton = bar.get_node("%%%sButton%d" % [bar.name, i + 1])
		button.slot = first_slot + i
		button.used.connect(on_used)
		buttons.append(button)
	return buttons


# Until the interface options exist, a bar shows whenever the server has an action in its slots.
static func update_visibility(bar: Control, buttons: Array[ActionButton]) -> void:
	var actions: PackedInt32Array = WowClient.session.get_action_buttons()
	var used: bool = false
	for button: ActionButton in buttons:
		used = used or (button.slot < actions.size() and actions[button.slot] != 0)
	bar.visible = used
