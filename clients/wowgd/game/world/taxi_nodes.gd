class_name TaxiNodes
extends RefCounted

# The flight points this character has found, as SMSG_SHOWTAXINODES' eight mask words.
const MASK_WORDS: int = 8
const SAVE_PATH: String = "user://taxi_nodes.cfg"

static var known_mask: PackedInt64Array = []
static var _nodes: WowDBC
static var _paths: WowDBC
static var _continents: WowDBC
# Direct routes out of each node: destination node id to [path id, cost].
static var _edges: Dictionary[int, Dictionary] = {}


static func is_known(node: int) -> bool:
	var word: int = (node - 1) / 32
	return word < known_mask.size() and known_mask[word] & (1 << ((node - 1) % 32)) != 0


# Saves the mask a flight master sent, so the world map knows the flight points next session.
static func remember(mask: PackedInt64Array) -> void:
	known_mask = mask
	var config: ConfigFile = ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("known", _character_key(), mask)
	config.save(SAVE_PATH)


static func load_known() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(SAVE_PATH)
	known_mask = config.get_value("known", _character_key(), PackedInt64Array())


static func all_on_map(map_id: int) -> Array[int]:
	_open()
	var ids: Array[int] = []
	for row: int in _nodes.row_count():
		if _nodes.get_uint(row, "MapID") == map_id:
			ids.append(_nodes.get_uint(row, "ID"))
	return ids


static func node_name(node: int) -> String:
	_open()
	var row: int = _nodes.find(node)
	return _nodes.get_string(row, "Name") if row >= 0 else ""


static func map_of(node: int) -> int:
	_open()
	var row: int = _nodes.find(node)
	return _nodes.get_uint(row, "MapID") if row >= 0 else -1


# The node in wire coordinates, x north and y west.
static func position(node: int) -> Vector3:
	_open()
	var row: int = _nodes.find(node)
	if row < 0:
		return Vector3.ZERO
	return Vector3(
		_nodes.get_float(row, "X"), _nodes.get_float(row, "Y"), _nodes.get_float(row, "Z"),
	)


# TaxiNodePosition: WorldMapContinent's taxi bounds, 0 to 1 from the flight map's west and north.
static func map_point(node: int) -> Vector2:
	_open()
	var map_id: int = map_of(node)
	for row: int in _continents.row_count():
		if _continents.get_uint(row, "MapID") != map_id:
			continue
		var at: Vector3 = position(node)
		var min_x: float = _continents.get_float(row, "TaxiMinX")
		var max_x: float = _continents.get_float(row, "TaxiMaxX")
		var min_y: float = _continents.get_float(row, "TaxiMinY")
		var max_y: float = _continents.get_float(row, "TaxiMaxY")
		return Vector2((max_y - at.y) / (max_y - min_y), (max_x - at.x) / (max_x - min_x))
	return Vector2(-1.0, -1.0)


# The cheapest chain of known nodes from one to the other, both ends included, or empty.
static func route(from: int, to: int) -> Array[int]:
	_open()
	var costs: Dictionary[int, int] = {from: 0}
	var previous: Dictionary[int, int] = {}
	var open: Array[int] = [from]
	while not open.is_empty():
		open.sort_custom(func(a: int, b: int) -> bool: return costs[a] < costs[b])
		var node: int = open.pop_front()
		if node == to:
			break
		var edges: Dictionary = _edges.get(node, {})
		for next: int in edges:
			if not is_known(next):
				continue
			var cost: int = costs[node] + int(edges[next][1])
			if not costs.has(next) or cost < costs[next]:
				costs[next] = cost
				previous[next] = node
				if next not in open:
					open.append(next)
	if not costs.has(to) or from == to:
		return []
	var chain: Array[int] = [to]
	while chain[0] != from:
		chain.push_front(previous[chain[0]])
	return chain


static func route_cost(chain: Array[int]) -> int:
	var total: int = 0
	for i: int in range(1, chain.size()):
		total += int((_edges.get(chain[i - 1], {}) as Dictionary).get(chain[i], [0, 0])[1])
	return total


static func neighbours(node: int) -> Array[int]:
	_open()
	var ids: Array[int] = []
	ids.assign((_edges.get(node, {}) as Dictionary).keys())
	return ids


static func _open() -> void:
	if _nodes != null:
		return
	var archive: WowArchive = WowAssets.archive
	_nodes = WowDBC.open(archive, "TaxiNodes")
	_paths = WowDBC.open(archive, "TaxiPath")
	_continents = WowDBC.open(archive, "WorldMapContinent")
	for row: int in _paths.row_count():
		var from: int = _paths.get_uint(row, "FromNode")
		if not _edges.has(from):
			_edges[from] = {}
		_edges[from][_paths.get_uint(row, "ToNode")] = [
			_paths.get_uint(row, "ID"), _paths.get_uint(row, "Cost"),
		]


static func _character_key() -> String:
	return str(WowClient.session.get_player_guid())
