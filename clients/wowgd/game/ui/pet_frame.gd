@tool
class_name PetFrame
extends UnitFrame

# PetFrame_SetHappiness: the three moods sit side by side in UI-PetHappiness.
const HAPPINESS_SIZE: Vector2 = Vector2(24.0, 23.0)

# Hunter pets are named by their owner, and only the query knows that name.
var _pet_name: String = ""


func _ready() -> void:
	if Engine.is_editor_hint():
		super()
		return
	_name_label = %PetName
	_health_bar = %PetFrameHealthBar
	_power_bar = %PetFrameManaBar
	_health_text = %PetFrameHealthBarText
	_power_text = %PetFrameManaBarText
	_portrait_rect = %PetPortrait
	for part: CanvasItem in [%PetFrameDropDown, %PetAttackModeTexture, %PetFrameHappiness]:
		part.hide()
	super()
	WowClient.session.packet_received.connect(_on_packet_received)
	WowClient.pet.changed.connect(_on_pet_changed)


func show_unit(unit: int) -> void:
	if unit != guid:
		_pet_name = ""
		if unit != 0:
			_query_name(unit)
	super(unit)


func _update_unit() -> void:
	if not _pet_name.is_empty():
		_name_label.text = _pet_name
	var happiness: Pet.Happiness = WowClient.pet.happiness()
	%PetFrameHappiness.visible = happiness != Pet.Happiness.NONE
	if %PetFrameHappiness.visible:
		var mood: AtlasTexture = (%PetFrameHappinessTexture as TextureRect).texture
		mood.region = Rect2(
			Vector2((Pet.Happiness.HAPPY - happiness) * HAPPINESS_SIZE.x, 0.0), HAPPINESS_SIZE
		)


func _on_pet_changed() -> void:
	show_unit(WowClient.pet.guid)


func _query_name(unit: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(12)
	payload.encode_u32(0, WowClient.session.get_field(unit, "UNIT_FIELD_PETNUMBER"))
	payload.encode_u64(4, unit)
	WowClient.session.send_packet("CMSG_PET_NAME_QUERY", payload)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_PET_NAME_QUERY_RESPONSE" or guid == 0:
		return
	var reader: PacketReader = PacketReader.new(payload)
	reader.u32()
	_pet_name = reader.cstring()
	refresh()
