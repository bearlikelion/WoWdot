class_name DressUpFrame
extends Control

signal close_requested
signal open_requested

const ROTATE_DEGREES_PER_SECOND: float = 120.0
const BACKGROUND: String = "Interface\\DressUpFrame\\DressUpBackground-%s%d.blp"
# DressUpTexturePath: gnomes and trolls borrow the dwarf and orc backgrounds.
const BACKGROUND_STAND_INS: Dictionary[String, String] = {"Gnome": "Dwarf", "Troll": "Orc"}

# Entries tried on since the last reset, in order, so a later one can replace an earlier.
var _tried: PackedInt32Array = []

@onready var _model: WowModelFrame = %DressUpModelModel
@onready var _left: BaseButton = %DressUpModelRotateLeftButton
@onready var _right: BaseButton = %DressUpModelRotateRightButton


func _ready() -> void:
	%DressUpFrameCloseButton.pressed.connect(close_requested.emit)
	%DressUpFrameCancelButton.pressed.connect(close_requested.emit)
	%DressUpFrameResetButton.pressed.connect(reset)
	(%DressUpFrameDescriptionText as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	WowClient.session.item_info_received.connect(_on_item_info_received)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var turn: float = float(_right.button_pressed) - float(_left.button_pressed)
	_model.facing += turn * ROTATE_DEGREES_PER_SECOND * delta


func set_portrait(texture: Texture2D) -> void:
	(%DressUpFramePortrait as TextureRect).texture = texture


# DressUpItem: the window opens on the player as they stand, then puts the item on.
func try_on(item_entry: int) -> void:
	if not is_visible_in_tree():
		_tried.clear()
		_set_background()
		open_requested.emit()
	_tried.append(item_entry)
	_dress()


func reset() -> void:
	_tried.clear()
	_dress()


func _dress() -> void:
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	var look: Dictionary = CharacterModels.player_look(session, guid)
	for entry: int in _tried:
		CharacterModels.try_on(look, session.get_item_info(entry))
	var display: int = session.get_field(guid, "UNIT_FIELD_DISPLAYID")
	_model.frame_character(WowAssets.creatures.instantiate(display, look))


func _set_background() -> void:
	var session: WowSession = WowClient.session
	var race: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_BYTES_0") & 0xFF
	var file: String = CharacterOptions.race_file(race)
	file = BACKGROUND_STAND_INS.get(file, file)
	var corners: Array[TextureRect] = [
		%DressUpBackgroundTopLeft, %DressUpBackgroundTopRight,
		%DressUpBackgroundBotLeft, %DressUpBackgroundBotRight,
	]
	for i: int in corners.size():
		var texture: WowTexture = WowTexture.new()
		texture.file = BACKGROUND % [file, i + 1]
		corners[i].texture = texture


# An item nobody has asked about yet is dressed once the server describes it.
func _on_item_info_received(entry: int) -> void:
	if is_visible_in_tree() and _tried.has(entry):
		_dress()
