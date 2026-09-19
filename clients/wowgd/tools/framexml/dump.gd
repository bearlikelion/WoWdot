class_name FrameXmlDump
extends SceneTree

# Run with `-s tools/framexml/dump.gd -- --out=<dir>`; the output is Blizzard data, so keep it out of the repo.

const SOURCES: PackedStringArray = [
	"Interface\\FrameXML\\*",
	"Interface\\GlueXML\\*",
	"Interface\\AddOns\\*.xml",
	"Interface\\AddOns\\*.lua",
]


func _initialize() -> void:
	var out: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=").path_join("")
	if out.is_empty():
		printerr("usage: -- --out=<directory outside the repo>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var archive: WowArchive = WowLoader.get_shared().archive
	var files: int = 0
	for mask: String in SOURCES:
		for path: String in archive.find(mask):
			var target: String = out.path_join(path.replace("\\", "/"))
			DirAccess.make_dir_recursive_absolute(target.get_base_dir())
			FileAccess.open(target, FileAccess.WRITE).store_buffer(archive.read(path))
			files += 1

	var sizes: Dictionary[String, Vector2i] = {}
	for path: String in archive.find("Interface\\*.blp"):
		var header: PackedByteArray = archive.read(path).slice(0, 20)
		if header.size() == 20:
			sizes[path.to_lower()] = Vector2i(header.decode_u32(12), header.decode_u32(16))
	var index: Dictionary = {}
	for path: String in sizes:
		index[path] = [sizes[path].x, sizes[path].y]
	FileAccess.open(out.path_join("textures.json"), FileAccess.WRITE).store_string(JSON.stringify(index))
	print("wrote %d interface files and %d texture sizes to %s" % [files, sizes.size(), out])
	quit()
