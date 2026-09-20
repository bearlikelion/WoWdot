class_name Pet
extends RefCounted

signal changed

# SMSG_PET_SPELLS action types, as UnitDefines' ActiveStates numbers them.
enum ActionState { DECIDE = 0x00, PASSIVE = 0x01, REACTION = 0x06, COMMAND = 0x07,
	DISABLED = 0x81, ENABLED = 0xC1 }
enum Command { STAY, FOLLOW, ATTACK, DISMISS }
enum Happiness { NONE, UNHAPPY, CONTENT, HAPPY }

const BAR_SLOTS: int = 10
const ACTION_MASK: int = 0xFFFFFF
# UNIT_FLAG_PET_RENAME: a pet that has just been tamed still needs a name.
const UNIT_FLAG_PET_RENAME: int = 0x10
const POWER_FOCUS: int = 2
# HAPPINESS_LEVEL_SIZE: the happiness power divides into three steps.
const HAPPINESS_STEP: int = 333000

var guid: int = 0
var actions: PackedInt32Array = []
var spells: PackedInt32Array = []
var command: int = 0
var react: int = 0

var _session: WowSession


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)


# CMSG_PET_ACTION: a packed action from the bar, aimed at whatever the player has targeted.
func send_action(packed: int) -> void:
	if guid == 0:
		return
	# The server answers a command with no packet, so the pet follows its own orders.
	var state: ActionState = ((packed >> 24) & 0xFF) as ActionState
	if state == ActionState.COMMAND:
		command = packed & ACTION_MASK
	elif state == ActionState.REACTION:
		react = packed & ACTION_MASK
	var payload: PackedByteArray = []
	payload.resize(20)
	payload.encode_u64(0, guid)
	payload.encode_u32(8, packed)
	payload.encode_u64(12, _session.get_field_guid(_session.get_player_guid(), "UNIT_FIELD_TARGET"))
	_session.send_packet("CMSG_PET_ACTION", payload)
	changed.emit()


# PetDismiss: the pet is sent away with a command the bar itself never holds.
func dismiss() -> void:
	send_action((ActionState.COMMAND << 24) | Command.DISMISS)


func set_autocast(spell: int, enabled: bool) -> void:
	if guid == 0:
		return
	var payload: PackedByteArray = []
	payload.resize(13)
	payload.encode_u64(0, guid)
	payload.encode_u32(8, spell)
	payload.encode_u8(12, int(enabled))
	_session.send_packet("CMSG_PET_SPELL_AUTOCAST", payload)


func rename(pet_name: String) -> void:
	if guid == 0:
		return
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, guid)
	payload.append_array(pet_name.to_utf8_buffer())
	payload.append(0)
	_session.send_packet("CMSG_PET_RENAME", payload)


func can_rename() -> bool:
	return guid != 0 \
	and _session.get_field(guid, "UNIT_FIELD_FLAGS") & UNIT_FLAG_PET_RENAME != 0


# Only hunter pets run on focus, and only they have happiness.
func is_hunter_pet() -> bool:
	return guid != 0 \
	and (_session.get_field(guid, "UNIT_FIELD_BYTES_0") >> 24) & 0xFF == POWER_FOCUS


func happiness() -> Happiness:
	if not is_hunter_pet():
		return Happiness.NONE
	var power: int = _session.get_field(guid, "UNIT_FIELD_POWER5")
	return clampi(power / HAPPINESS_STEP + 1, Happiness.UNHAPPY, Happiness.HAPPY) as Happiness


func spell_of(packed: int) -> int:
	return packed & ACTION_MASK


func state_of(packed: int) -> ActionState:
	return ((packed >> 24) & 0xFF) as ActionState


# SMSG_PET_SPELLS: the pet, its stance, the ten bar slots, then the spells it knows.
func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_PET_SPELLS":
		return
	var reader: PacketReader = PacketReader.new(payload)
	guid = reader.u64()
	actions.clear()
	spells.clear()
	if guid != 0:
		reader.u32()
		react = reader.u8()
		command = reader.u8()
		reader.u8()
		reader.u8()
		for i: int in BAR_SLOTS:
			actions.append(reader.u32())
		for i: int in reader.u8():
			spells.append(reader.u32())
	changed.emit()
