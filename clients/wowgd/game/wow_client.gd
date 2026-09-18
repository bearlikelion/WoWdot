extends Node

var session: WowSession = WowSession.new()


func _process(_delta: float) -> void:
	session.poll()


func map_name(map_id: int) -> String:
	var maps: WowDBC = WowDBC.open(WowAssets.archive, "Map")
	var row: int = maps.find(map_id)
	return maps.get_string(row, "InternalName") if row >= 0 else ""
