class_name PetActionBar
extends Control

# The commands and reactions the stock bar draws instead of a spell icon.
const COMMAND_ICONS: Dictionary[Pet.Command, String] = {
	Pet.Command.STAY: "Interface\\Icons\\Spell_Nature_TimeStop.blp",
	Pet.Command.FOLLOW: "Interface\\Icons\\Ability_Tracking.blp",
	Pet.Command.ATTACK: "Interface\\Icons\\Ability_GhoulFrenzy.blp",
	Pet.Command.DISMISS: "Interface\\Icons\\Spell_Shadow_Teleport.blp",
}
const REACTION_ICONS: Dictionary[int, String] = {
	0: "Interface\\Icons\\Ability_Seal.blp",
	1: "Interface\\Icons\\Ability_Defend.blp",
	2: "Interface\\Icons\\Ability_Racial_BloodRage.blp",
}

var _buttons: Array[ActionButton] = []


func _ready() -> void:
	for i: int in Pet.BAR_SLOTS:
		var button: ActionButton = get_node("%%PetActionButton%d" % (i + 1))
		button.pressed.connect(_on_button_pressed.bind(i))
		button.gui_input.connect(_on_button_input.bind(i))
		_buttons.append(button)
	WowClient.pet.changed.connect(refresh)
	hide()


func use(index: int) -> void:
	var pet: Pet = WowClient.pet
	if index >= 0 and index < pet.actions.size():
		pet.send_action(pet.actions[index])


func refresh() -> void:
	var pet: Pet = WowClient.pet
	visible = pet.guid != 0 and not pet.actions.is_empty()
	if not visible:
		return
	for i: int in Pet.BAR_SLOTS:
		var packed: int = pet.actions[i] if i < pet.actions.size() else 0
		var state: Pet.ActionState = pet.state_of(packed)
		var action: int = pet.spell_of(packed)
		var button: ActionButton = _buttons[i]
		button.command_icon = _icon_of(state, action)
		button.stance_spell = action if button.command_icon.is_empty() else 0
		button.stance_active = _is_active(pet, state, action)
		button.visible = packed != 0


func _icon_of(state: Pet.ActionState, action: int) -> String:
	if state == Pet.ActionState.COMMAND:
		return COMMAND_ICONS.get(action as Pet.Command, "")
	if state == Pet.ActionState.REACTION:
		return REACTION_ICONS.get(action, "")
	return ""


# ponytail: an autocasting spell reads as checked; the stock bar spins its own glow instead.
func _is_active(pet: Pet, state: Pet.ActionState, action: int) -> bool:
	if state == Pet.ActionState.COMMAND:
		return action == pet.command
	if state == Pet.ActionState.REACTION:
		return action == pet.react
	return state == Pet.ActionState.ENABLED


func _on_button_pressed(index: int) -> void:
	use(index)


# TogglePetAutocast: a right-click turns a pet spell's own casting on and off.
func _on_button_input(event: InputEvent, index: int) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT:
		return
	get_viewport().set_input_as_handled()
	var pet: Pet = WowClient.pet
	if index >= pet.actions.size():
		return
	var state: Pet.ActionState = pet.state_of(pet.actions[index])
	if state != Pet.ActionState.ENABLED and state != Pet.ActionState.DISABLED:
		return
	# The server keeps the new state to itself, so the bar shows it at once.
	var enabled: bool = state == Pet.ActionState.DISABLED
	pet.set_autocast(pet.spell_of(pet.actions[index]), enabled)
	pet.actions[index] = (
		(Pet.ActionState.ENABLED if enabled else Pet.ActionState.DISABLED) << 24
	) | pet.spell_of(pet.actions[index])
	refresh()
