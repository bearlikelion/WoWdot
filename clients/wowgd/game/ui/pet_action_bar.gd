class_name PetActionBar
extends Control

# SMSG_PET_SPELLS action types, as UnitDefines' ActiveStates numbers them.
enum ActionState { DECIDE = 0x00, PASSIVE = 0x01, REACTION = 0x06, COMMAND = 0x07,
	DISABLED = 0x81, ENABLED = 0xC1 }
# The commands and reactions the stock bar draws instead of a spell icon.
enum Command { STAY, FOLLOW, ATTACK, DISMISS }

const BUTTON_COUNT: int = 10
const ACTION_MASK: int = 0xFFFFFF
const COMMAND_ICONS: Dictionary[Command, String] = {
	Command.STAY: "Interface\\Icons\\Spell_Nature_TimeStop.blp",
	Command.FOLLOW: "Interface\\Icons\\Ability_Tracking.blp",
	Command.ATTACK: "Interface\\Icons\\Ability_GhoulFrenzy.blp",
	Command.DISMISS: "Interface\\Icons\\Spell_Shadow_Teleport.blp",
}
const REACTION_ICONS: Dictionary[int, String] = {
	0: "Interface\\Icons\\Ability_Seal.blp",
	1: "Interface\\Icons\\Ability_Defend.blp",
	2: "Interface\\Icons\\Ability_Racial_BloodRage.blp",
}

var _guid: int = 0
var _actions: PackedInt32Array = []
var _command: int = 0
var _react: int = 0
var _buttons: Array[ActionButton] = []


func _ready() -> void:
	for i: int in BUTTON_COUNT:
		var button: ActionButton = get_node("%%PetActionButton%d" % (i + 1))
		button.pressed.connect(_on_button_pressed.bind(i))
		_buttons.append(button)
	WowClient.session.packet_received.connect(_on_packet_received)
	hide()


# CMSG_PET_ACTION carries the packed action the bar was given, and who it is aimed at.
func use(index: int) -> void:
	if _guid == 0 or index < 0 or index >= _actions.size():
		return
	var packed: int = _actions[index]
	# The server answers no command with a packet, so the bar follows its own clicks.
	var state: ActionState = ((packed >> 24) & 0xFF) as ActionState
	if state == ActionState.COMMAND:
		_command = packed & ACTION_MASK
	elif state == ActionState.REACTION:
		_react = packed & ACTION_MASK
	_send(packed)
	refresh()


# PetDismiss: the pet is sent away with a command the bar itself never holds.
func dismiss() -> void:
	if _guid != 0:
		_send((ActionState.COMMAND << 24) | Command.DISMISS)


func _send(packed: int) -> void:
	var session: WowSession = WowClient.session
	var payload: PackedByteArray = []
	payload.resize(20)
	payload.encode_u64(0, _guid)
	payload.encode_u32(8, packed)
	payload.encode_u64(12, session.get_field_guid(session.get_player_guid(), "UNIT_FIELD_TARGET"))
	session.send_packet("CMSG_PET_ACTION", payload)


func refresh() -> void:
	visible = _guid != 0 and not _actions.is_empty()
	if not visible:
		return
	for i: int in BUTTON_COUNT:
		var packed: int = _actions[i] if i < _actions.size() else 0
		var state: ActionState = ((packed >> 24) & 0xFF) as ActionState
		var action: int = packed & ACTION_MASK
		var button: ActionButton = _buttons[i]
		button.command_icon = _icon_of(state, action)
		button.stance_spell = action if button.command_icon.is_empty() else 0
		button.stance_active = _is_active(state, action)
		button.visible = packed != 0


func _icon_of(state: ActionState, action: int) -> String:
	if state == ActionState.COMMAND:
		return COMMAND_ICONS.get(action as Command, "")
	if state == ActionState.REACTION:
		return REACTION_ICONS.get(action, "")
	return ""


# ponytail: an autocasting spell reads as checked; the stock bar spins its own glow instead.
func _is_active(state: ActionState, action: int) -> bool:
	if state == ActionState.COMMAND:
		return action == _command
	if state == ActionState.REACTION:
		return action == _react
	return state == ActionState.ENABLED


func _on_button_pressed(index: int) -> void:
	use(index)


# SMSG_PET_SPELLS: the pet, its stance, the ten bar slots, then the spells it knows.
func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_PET_SPELLS":
		return
	var reader: PacketReader = PacketReader.new(payload)
	_guid = reader.u64()
	_actions.clear()
	if _guid != 0:
		reader.u32()
		_react = reader.u8()
		_command = reader.u8()
		reader.u8()
		reader.u8()
		for i: int in BUTTON_COUNT:
			_actions.append(reader.u32())
	refresh()
