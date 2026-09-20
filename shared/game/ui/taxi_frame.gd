class_name TaxiFrame
extends Control

signal close_requested
signal open_requested
signal error_raised(text: String)

enum NodeType { NONE, CURRENT, REACHABLE, DISTANT }

const TAXI_BUTTON: PackedScene = preload("res://game/ui/wow/taxi_button.tscn")
const MAP_PATH: String = "Interface\\TaxiFrame\\TAXIMAP%d.blp"
const ICONS: Dictionary[NodeType, String] = {
	NodeType.CURRENT: "Interface\\TaxiFrame\\UI-Taxi-Icon-Green.blp",
	NodeType.REACHABLE: "Interface\\TaxiFrame\\UI-Taxi-Icon-White.blp",
	NodeType.DISTANT: "Interface\\TaxiFrame\\UI-Taxi-Icon-Yellow.blp",
}
const LINE_TEXTURE: String = "Interface\\TaxiFrame\\UI-Taxi-Line.blp"
const LINE_WIDTH: float = 32.0
# SMSG_ACTIVATETAXIREPLY codes after 0, which is the flight starting.
const REPLY_ERRORS: PackedStringArray = [
	"", "ERR_TAXIUNSPECIFIEDSERVERERROR", "ERR_TAXINOSUCHPATH", "ERR_TAXINOTENOUGHMONEY",
	"ERR_TAXITOOFARAWAY", "ERR_TAXINOVENDORNEARBY", "ERR_TAXINOTVISITED", "ERR_TAXIPLAYERBUSY",
	"ERR_TAXIPLAYERALREADYMOUNTED", "ERR_TAXIPLAYERSHAPESHIFTED", "ERR_TAXIPLAYERMOVING",
	"ERR_TAXISAMENODE", "ERR_TAXINOTSTANDING",
]
const YOU_ARE_HERE: Color = Color(0.5, 1.0, 0.5)
const PORTRAIT: PackedScene = preload("res://game/ui/unit_portrait.tscn")
const PORTRAIT_MASK: Shader = preload("res://game/ui/portrait.gdshader")

var _guid: int = 0
var _current: int = 0
var _types: Dictionary[int, NodeType] = {}
var _buttons: Dictionary[int, WowButton] = {}
var _icons: Dictionary[NodeType, WowTexture] = {}
var _line_texture: WowTexture = WowTexture.new()
var _portrait: UnitPortrait

@onready var _map: TextureRect = %TaxiMap
@onready var _routes: Control = %TaxiRouteMap


func _ready() -> void:
	for type: NodeType in ICONS:
		var icon: WowTexture = WowTexture.new()
		icon.file = ICONS[type]
		_icons[type] = icon
	_line_texture.file = LINE_TEXTURE
	%TaxiCloseButton.pressed.connect(close_requested.emit)
	_portrait = PORTRAIT.instantiate()
	add_child(_portrait)
	var mask: ShaderMaterial = ShaderMaterial.new()
	mask.shader = PORTRAIT_MASK
	%TaxiPortrait.material = mask
	%TaxiPortrait.texture = _portrait.get_texture()
	var session: WowSession = WowClient.session
	session.taxi_nodes_received.connect(_on_nodes_received)
	session.taxi_reply_received.connect(_on_reply_received)


# TAXIMAP_OPENED: a button per known node on the continent's flight map.
func _on_nodes_received(taxi: Dictionary) -> void:
	_guid = taxi["guid"]
	_current = taxi["current"]
	TaxiNodes.remember(taxi["mask"])
	var map_id: int = TaxiNodes.map_of(_current)
	var map_texture: WowTexture = WowTexture.new()
	map_texture.file = MAP_PATH % map_id
	_map.texture = map_texture
	%TaxiMerchant.text = WowClient.session.get_object_name(_guid)
	_portrait.show_unit(_guid)
	for button: WowButton in _buttons.values():
		button.queue_free()
	_buttons.clear()
	_types.clear()
	_clear_lines()
	for node: int in TaxiNodes.all_on_map(map_id):
		var type: NodeType = _node_type(node)
		if type == NodeType.NONE:
			continue
		_types[node] = type
		var button: WowButton = TAXI_BUTTON.instantiate()
		_routes.add_child(button)
		button.texture_normal = _icons[type]
		button.position = TaxiNodes.map_point(node) * _map.size - button.size / 2.0
		button.pressed.connect(_on_node_pressed.bind(node))
		button.mouse_entered.connect(_on_node_entered.bind(node, button))
		button.mouse_exited.connect(_on_node_left.bind(button))
		_buttons[node] = button
	open_requested.emit()


# TaxiNodeGetType: here, reachable through known nodes, or known but cut off.
func _node_type(node: int) -> NodeType:
	if node == _current:
		return NodeType.CURRENT
	if not TaxiNodes.is_known(node):
		return NodeType.NONE
	return NodeType.REACHABLE if not TaxiNodes.route(_current, node).is_empty() \
	else NodeType.DISTANT


# TaxiNodeOnButtonEnter: the cost and the route there, or every flight out of here.
func _on_node_entered(node: int, button: WowButton) -> void:
	var tooltip: GameTooltip = GameTooltip.current
	if tooltip:
		tooltip.begin(button, GameTooltip.TooltipAnchor.RIGHT, button)
		tooltip.add_line(TaxiNodes.node_name(node))
	_clear_lines()
	match _types[node]:
		NodeType.REACHABLE:
			var chain: Array[int] = TaxiNodes.route(_current, node)
			for i: int in range(1, chain.size()):
				_add_line(chain[i - 1], chain[i])
			if tooltip:
				var cost: int = TaxiNodes.route_cost(chain)
				tooltip.add_line(WowStrings.get_text("COSTS_LABEL") + " " + _money_text(cost))
		NodeType.CURRENT:
			for next: int in TaxiNodes.neighbours(_current):
				if TaxiNodes.is_known(next):
					_add_line(_current, next)
			if tooltip:
				tooltip.add_line(WowStrings.get_text("TAXINODEYOUAREHERE"), YOU_ARE_HERE)
	if tooltip:
		tooltip.present()


func _on_node_left(button: WowButton) -> void:
	_clear_lines()
	if GameTooltip.current:
		GameTooltip.current.hide_for(button)


# TakeTaxiNode: one hop flies straight there, more go by the express route.
func _on_node_pressed(node: int) -> void:
	if _types.get(node, NodeType.NONE) != NodeType.REACHABLE:
		return
	var chain: Array[int] = TaxiNodes.route(_current, node)
	var payload: PackedByteArray = PackedByteArray()
	if chain.size() == 2:
		payload.resize(16)
		payload.encode_u64(0, _guid)
		payload.encode_u32(8, _current)
		payload.encode_u32(12, node)
		WowClient.session.send_packet("CMSG_ACTIVATETAXI", payload)
		return
	payload.resize(16 + chain.size() * 4)
	payload.encode_u64(0, _guid)
	payload.encode_u32(8, TaxiNodes.route_cost(chain))
	payload.encode_u32(12, chain.size())
	for i: int in chain.size():
		payload.encode_u32(16 + i * 4, chain[i])
	WowClient.session.send_packet("CMSG_ACTIVATETAXIEXPRESS", payload)


func _on_reply_received(code: int) -> void:
	if code == 0:
		close_requested.emit()
	elif code < REPLY_ERRORS.size():
		error_raised.emit(WowStrings.get_text(REPLY_ERRORS[code]))


# DrawRouteLine: the dotted route texture stretched between two nodes.
func _add_line(from: int, to: int) -> void:
	var line: Line2D = Line2D.new()
	line.texture = _line_texture
	line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	line.width = LINE_WIDTH
	line.add_point(TaxiNodes.map_point(from) * _map.size)
	line.add_point(TaxiNodes.map_point(to) * _map.size)
	_routes.add_child(line)
	_routes.move_child(line, 0)


func _clear_lines() -> void:
	for child: Node in _routes.get_children():
		if child is Line2D:
			child.queue_free()


func _money_text(copper: int) -> String:
	var parts: PackedStringArray = []
	if copper >= 10000:
		parts.append("%dg" % floori(copper / 10000.0))
	if copper >= 100:
		parts.append("%ds" % floori((copper % 10000) / 100.0))
	parts.append("%dc" % (copper % 100))
	return " ".join(parts)
