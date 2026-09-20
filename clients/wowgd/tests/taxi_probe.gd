extends SceneTree


func _initialize() -> void:
	var archive: WowArchive = WowArchive.new()
	archive.open(ProjectSettings.get_setting("wowgd/client_data_dir"))
	var nodes: WowDBC = WowDBC.open(archive, "TaxiPathNode")
	var wanted: PackedInt32Array = [241, 285, 292, 293, 295, 301, 302, 303]
	for path: int in wanted:
		var maps: Dictionary[int, bool] = {}
		var count: int = 0
		var first: Vector3 = Vector3.ZERO
		for row: int in nodes.row_count():
			if nodes.get_uint(row, "PathID") != path:
				continue
			maps[nodes.get_uint(row, "MapID")] = true
			if count == 0:
				first = Vector3(
					nodes.get_float(row, "X"), nodes.get_float(row, "Y"), nodes.get_float(row, "Z")
				)
			count += 1
		print("path %d: %d nodes, maps %s, first %v" % [path, count, maps.keys(), first])
	quit()
