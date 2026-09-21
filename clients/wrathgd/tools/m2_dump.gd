class_name M2Dump
extends SceneTree

# Prints a model's batches and textures, to work out what a glue scene draws:
# godot --headless --path . --script tools/m2_dump.gd -- "Interface\Glues\Models\UI_MainMenu\UI_MainMenu.m2"


func _initialize() -> void:
	for path: String in OS.get_cmdline_user_args():
		_dump(path)
	quit()


func _dump(path: String) -> void:
	var loader: WowLoader = WowLoader.get_shared()
	var info: Dictionary = loader.get_m2_info(path)
	if info.is_empty():
		print("%s: nothing read" % path)
		return
	var node: Node3D = loader.load_m2(path)
	if node != null:
		var box: AABB = AABB()
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			box = box.merge(mesh.get_aabb()) if box.size != Vector3.ZERO else mesh.get_aabb()
		print("  extent %v from %v" % [box.size, box.position])
		for player: AnimationPlayer in node.find_children("*", "AnimationPlayer", true, false):
			for name: String in player.get_animation_list():
				var clip: Animation = player.get_animation(name)
				print("  %s/%s: %.2fs, %d tracks, loop %d" % [
					player.name, name, clip.length, clip.get_track_count(), clip.loop_mode,
				])
				if OS.get_environment("M2_DUMP_TRACKS") != "":
					for track: int in clip.get_track_count():
						print("    %s" % clip.track_get_path(track))
			print("  %s autoplay '%s'" % [player.name, player.autoplay])
		node.free()
	for camera: Dictionary in info.get("cameras", []):
		print("  camera fov %.4f rad (%.1f deg) at %v looking at %v" % [
			camera["fov"], rad_to_deg(camera["fov"]), camera["position"], camera["target"],
		])
	for attachment: Dictionary in info.get("attachments", []):
		print("  attachment %d at %v" % [attachment["id"], attachment["position"]])
	var stem: String = path.get_basename()
	print("  files: %s" % [loader.get_archive().find(stem + "*")])
	var textures: Array = info["textures"]
	print("%s: version %d, %d bones, %d batches, %d textures, %d animations" % [
		path.get_file(), info["version"], info["bones"], (info["batches"] as Array).size(),
		textures.size(),
		(info["animations"] as PackedStringArray).size(),
	])
	for entry: Dictionary in textures:
		var file: String = entry["file"]
		if not file.is_empty() and loader.load_image(file) == null:
			print("  MISSING %s" % file)
	for batch: Dictionary in info["batches"]:
		var texture: String = ""
		if batch["texture"] >= 0 and batch["texture"] < textures.size():
			texture = String(textures[batch["texture"]]["file"]).get_file()
		print("  geoset %4d blend %d flags %2d textures %d anim %2d tint %s  %s" % [
			batch["geoset"], batch["blend"], batch["flags"], batch["texture_count"],
			batch["texture_animation"], batch["tint"], texture,
		])

