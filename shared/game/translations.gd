class_name Translations
extends RefCounted

# Community translations for locales the client's MPQs lack, one key,text CSV per locale.

# In DBC locale column order, each named in its own language.
const LOCALES: Dictionary[String, String] = {
	"enUS": "English", "koKR": "한국어", "frFR": "Français", "deDE": "Deutsch",
	"zhCN": "简体中文", "zhTW": "繁體中文", "esES": "Español (España)", "esMX": "Español (México)",
}

static var strings: Dictionary[String, String] = {}


# Beside the executable in a release; in the editor, the repo's translations/<project> folder.
static func directory() -> String:
	if OS.has_feature("editor"):
		var project: String = String(ProjectSettings.get_setting("application/config/name"))
		return ProjectSettings.globalize_path("res://").path_join("../../translations") \
				.path_join(project.to_lower()).simplify_path()
	return OS.get_executable_path().get_base_dir().path_join("translations")


# Scaffolded files list every key with empty text until someone translates one.
static func has_locale(locale: String) -> bool:
	var text: String = FileAccess.get_file_as_string(directory().path_join(locale + ".csv"))
	return RegEx.create_from_string("\\n[^,\\n]+,[^\\r\\n]").search(text) != null


static func clear() -> void:
	strings.clear()
	WowDBC.set_translations(strings)


static func load_locale(locale: String) -> void:
	strings.clear()
	var file: FileAccess = FileAccess.open(directory().path_join(locale + ".csv"), FileAccess.READ)
	if file != null:
		file.get_csv_line()
		while not file.eof_reached():
			var line: PackedStringArray = file.get_csv_line()
			if line.size() >= 2 and not line[1].is_empty():
				strings[line[0]] = line[1]
	WowDBC.set_translations(strings)
