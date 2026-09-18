class_name TestData
extends SceneTree

const ICON_PATH: String = "Interface\\Icons\\INV_Misc_QuestionMark.blp"
const ICON_PNG: String = "user://inv_misc_questionmark.png"

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run()
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("test_data: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _run() -> void:
	var archive: WowArchive = WowArchive.new()
	var data_dir: String = ProjectSettings.get_setting("wowgd/client_data_dir")
	_check(archive.open(data_dir) == OK, "open " + data_dir)
	print("archives: ", archive.get_archive_names())

	var maps: WowDBC = WowDBC.open(archive, "Map")
	_check(maps != null, "Map.dbc opens")
	if maps:
		var row: int = maps.find(0)
		_check(row >= 0, "Map.dbc has id 0")
		_check(maps.get_string(row, "InternalName") == "Azeroth", "map 0 is Azeroth")
		print("Map.dbc: %d rows, %d fields" % [maps.row_count(), maps.field_count()])

	var loader: WowLoader = WowLoader.new()
	loader.archive = archive
	var icon: ImageTexture = loader.load_texture(ICON_PATH)
	_check(icon != null and icon.get_size() == Vector2(64, 64), "question mark icon is 64x64")
	_check(loader.load_texture(ICON_PATH) == icon, "textures are cached")
	if icon:
		icon.get_image().save_png(ICON_PNG)
		print("wrote ", ProjectSettings.globalize_path(ICON_PNG))

	var wolves: PackedStringArray = archive.find("Creature\\Wolf\\*")
	print("Creature\\Wolf: ", wolves)
	_check(archive.has("Creature\\Wolf\\Wolf.mdx"), "model found by its .mdx name")

	var wow: Vector3 = Vector3(-8949.95, -132.493, 83.5312)
	_check(WowCoords.from_godot(WowCoords.to_godot(wow)).is_equal_approx(wow), "coords round trip")
	_check(WowCoords.to_godot(Vector3(1, 0, 0)) == Vector3(0, 0, -1), "wow north is godot -Z")


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)
