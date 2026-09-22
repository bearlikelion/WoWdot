class_name ChatBubbles
extends Control

const BUBBLE: PackedScene = preload("res://ui/wow/chat_bubble.tscn")
# Speech floats over the speaker for this long, fading out at the end.
const DURATION: float = 10.0
const FADE_TIME: float = 1.0
const MAX_WIDTH: float = 300.0
const PADDING: Vector2 = Vector2(18.0, 12.0)
const HEAD_GAP: float = 24.0
# The tail hangs from the bubble's bottom edge, tucked under the border by this much.
const TAIL_OVERLAP: float = 5.0
const BUBBLE_TYPES: Array[WowSession.ChatType] = [
	WowSession.CHAT_SAY, WowSession.CHAT_YELL,
	WowSession.CHAT_MONSTER_SAY, WowSession.CHAT_MONSTER_YELL,
]

@export var entities: Entities
@export var player: Player

var _bubbles: Dictionary[int, Control] = {}


func _ready() -> void:
	WowClient.session.chat_received.connect(_on_chat_received)


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	for guid: int in _bubbles.keys():
		var bubble: Control = _bubbles[guid]
		var head: Vector3 = _head_position(guid)
		bubble.visible = head != Vector3.ZERO and not camera.is_position_behind(head)
		if bubble.visible:
			var at: Vector2 = camera.unproject_position(head)
			var tail: Control = bubble.get_node("%Tail")
			var drop: float = tail.size.y - TAIL_OVERLAP
			bubble.position = at - Vector2(bubble.size.x * 0.5, bubble.size.y + HEAD_GAP + drop)


# The player's own model is not one of the entities, so their head comes from the body.
func _head_position(guid: int) -> Vector3:
	if guid == WowClient.session.get_player_guid():
		return player.head_position()
	return entities.head_position(guid)


func _on_chat_received(line: Dictionary) -> void:
	var settings: InterfaceSettings = WowAssets.interface
	var kind: WowSession.ChatType = line["type"] as WowSession.ChatType
	var party: bool = kind == WowSession.CHAT_PARTY
	if not settings.is_on(&"chat_bubbles"):
		return
	if not BUBBLE_TYPES.has(kind) and not (party and settings.is_on(&"party_chat_bubbles")):
		return
	var guid: int = line["sender_guid"]
	if guid == 0:
		return
	if _bubbles.has(guid):
		_bubbles[guid].queue_free()
	_bubbles[guid] = _add_bubble(guid, line["text"])


func _add_bubble(guid: int, text: String) -> Control:
	var bubble: Control = BUBBLE.instantiate()
	add_child(bubble)
	var label: Label = bubble.get_node("%Text")
	var wrapped: Vector2 = label.get_theme_font(&"font").get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_CENTER, MAX_WIDTH, label.get_theme_font_size(&"font_size")
	)
	label.text = text
	bubble.size = wrapped + PADDING * 2.0
	var tail: TextureRect = bubble.get_node("%Tail")
	tail.size = tail.texture.get_size()
	tail.position = Vector2((bubble.size.x - tail.size.x) * 0.5, bubble.size.y - TAIL_OVERLAP)
	bubble.hide()
	var fade: Tween = bubble.create_tween()
	fade.tween_property(bubble, "modulate:a", 0.0, FADE_TIME).set_delay(DURATION - FADE_TIME)
	fade.tween_callback(func() -> void: _remove(guid))
	return bubble


func _remove(guid: int) -> void:
	if _bubbles.has(guid):
		_bubbles[guid].queue_free()
		_bubbles.erase(guid)
