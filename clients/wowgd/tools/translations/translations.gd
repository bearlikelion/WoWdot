class_name TranslationsTool
extends SceneTree

# Run with `-s tools/translations/translations.gd -- --export=<file>` for the English source, which
# is Blizzard data, so keep it out of the repo; `-- --check=<locale>` checks that locale's CSV, and
# `-- --scaffold` brings every locale's CSV up to the current keys.

# Every DBC column the client reads with get_text.
const FIELDS: Array[Array] = [
	["AreaTable", "Name"], ["AreaPOI", "Name"], ["AreaPOI", "Description"],
	["ChatChannels", "Name"], ["ChrClasses", "Name"], ["ChrRaces", "Name"], ["CreatureFamily", 8],
	["CreatureType", "Name"], ["EmotesTextData", 1], ["Faction", "Name"],
	["Faction", "Description"], ["GameTips", 1], ["GMTicketCategory", 1],
	["ItemRandomProperties", 7], ["ItemSubClass", 10], ["Map", "MapName"], ["QuestInfo", "Name"],
	["QuestSort", "Name"], ["SkillLine", "Name"], ["SkillLine", "Description"],
	["SkillLineCategory", "Name"], ["Spell", "Name"], ["Spell", "Rank"], ["Spell", "Description"],
	["Spell", "Tooltip"], ["SpellRange", "Name"], ["TalentTab", "Name"], ["TaxiNodes", "Name"],
	["WorldStateUI", 4],
]


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--export="):
			quit(_export(arg.trim_prefix("--export=")))
			return
		if arg.begins_with("--check="):
			quit(_check(arg.trim_prefix("--check="), "--complete" in OS.get_cmdline_user_args()))
			return
		if arg == "--scaffold":
			quit(_scaffold())
			return
	printerr("usage: -- --export=<file outside the repo> | --check=<locale> [--complete] | --scaffold")
	quit(1)


func _export(path: String) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("cannot write %s" % path)
		return 1
	var source: Dictionary[String, String] = _source()
	file.store_csv_line(["key", "text"])
	for key: String in source:
		file.store_csv_line([key, source[key]])
	print("wrote %d strings to %s" % [source.size(), path])
	return 0


func _check(locale: String, complete: bool = false) -> int:
	if locale == "enUS" or not Translations.LOCALES.has(locale):
		printerr("unknown translation locale: %s" % locale)
		return 1
	var temporary: String = OS.get_environment("TMPDIR")
	if temporary.is_empty():
		temporary = OS.get_environment("TEMP") if OS.get_name() == "Windows" else "/tmp"
	var source: String = temporary.path_join(
		"wowgd-source-%d-%d.csv" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	if _export(source) != 0:
		return 1
	var arguments: PackedStringArray = [
		ProjectSettings.globalize_path("res://tools/translations/batches.py"),
		"check", "--source", source,
		"--file", Translations.directory().path_join(locale + ".csv"),
	]
	if complete:
		arguments.append("--complete")
	var output: Array = []
	var python: String = "python" if OS.get_name() == "Windows" else "python3"
	var result: int = OS.execute(python, arguments, output, true)
	DirAccess.remove_absolute(source)
	for line: String in output:
		print(line.strip_edges())
	if result == -1:
		printerr("translation checking requires Python 3")
	return 0 if result == 0 else 1


# Keeps every translation whose key still exists and adds the new keys with empty text.
func _scaffold() -> int:
	var source: Dictionary[String, String] = _source()
	for locale: String in Translations.LOCALES:
		if locale == "enUS":
			continue
		var path: String = Translations.directory().path_join(locale + ".csv")
		var kept: Dictionary[String, String] = {}
		var old: FileAccess = FileAccess.open(path, FileAccess.READ)
		if old != null:
			old.get_csv_line()
			while not old.eof_reached():
				var line: PackedStringArray = old.get_csv_line()
				if line.size() == 2 and not line[1].is_empty():
					kept[line[0]] = line[1]
			old.close()
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			printerr("cannot write %s" % path)
			return 1
		file.store_csv_line(["key", "text"])
		var translated: int = 0
		for key: String in source:
			file.store_csv_line([key, kept.get(key, "")])
			translated += 1 if kept.has(key) else 0
		print("%s: %d keys, %d translated" % [locale, source.size(), translated])
	return 0


# The English text by translation key, from the client's own MPQs.
func _source() -> Dictionary[String, String]:
	var source: Dictionary[String, String] = {}
	var archive: WowArchive = WowLoader.get_shared().archive
	for field: Array in FIELDS:
		var table: WowDBC = WowDBC.open(archive, field[0])
		for row: int in table.row_count():
			var text: String = table.get_string(row, field[1])
			if not text.is_empty():
				source[table.text_key(row, field[1])] = text
	var strings: Dictionary[String, String] = WowStrings.all_texts()
	var keys: Array[String] = strings.keys()
	keys.sort()
	for key: String in keys:
		source[key] = strings[key]
	return source

