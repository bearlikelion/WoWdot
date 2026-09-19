@tool
class_name GDDocsBuilder
extends RefCounted

# Gathers the project's documentation and writes it out as one offline HTML page.

const SETTING_OUTPUT: String = "gddocs/output_path"
const SETTING_EXCLUDE: String = "gddocs/exclude"
const SETTING_GUIDES: String = "gddocs/guides"
const SETTING_FALLBACK: String = "gddocs/plain_comment_fallback"

const DEFAULT_OUTPUT: String = "res://docs/api/index.html"
const DEFAULT_EXCLUDE: PackedStringArray = ["res://addons/"]
const DEFAULT_GUIDES: PackedStringArray = ["res://README.md", "res://docs/"]

const WEB_DIR: String = "res://addons/gddocs/web/"
const PLACEHOLDER: String = "<!-- GDDOCS -->"
const USAGE_EXTENSIONS: PackedStringArray = ["tscn", "scn", "tres", "res"]
const DECLARATION_KEYS: Dictionary[String, String] = {
	"func": "method",
	"var": "member",
	"const": "constant",
	"signal": "signal",
	"enum": "enum",
}


static func build() -> Error:
	var data: Dictionary = collect()
	if data.is_empty():
		return FAILED
	return write(data)


static func output_path() -> String:
	return String(ProjectSettings.get_setting(SETTING_OUTPUT, DEFAULT_OUTPUT))


# Empty when the doctool run fails; the error is already printed.
static func collect() -> Dictionary:
	var xml_dir: DirAccess = _run_doctool()
	if xml_dir == null:
		return {}

	var exclude: PackedStringArray = _setting_list(SETTING_EXCLUDE, DEFAULT_EXCLUDE)
	var parents: Dictionary[String, String] = {}
	var class_paths: Dictionary[String, String] = {}
	for engine_class: String in ClassDB.get_class_list():
		parents[engine_class] = String(ClassDB.get_parent_class(engine_class))
	for info: Dictionary in ProjectSettings.get_global_class_list():
		parents[String(info["class"])] = String(info["base"])
		class_paths[String(info["class"])] = String(info["path"])
	# The doctool names a script autoload after the autoload rather than its path.
	var autoloads: Array[Dictionary] = _autoloads()
	for autoload: Dictionary in autoloads:
		if String(autoload["path"]).get_extension() == "gd":
			class_paths[String(autoload["name"])] = String(autoload["path"])

	var fallback: bool = bool(ProjectSettings.get_setting(SETTING_FALLBACK, true))
	var name_pattern: RegEx = RegEx.create_from_string("<class name=\"([^\"]+)\"")
	var classes: Array[Dictionary] = []
	var comments: Dictionary = {}
	for file_name: String in DirAccess.get_files_at(xml_dir.get_current_dir()):
		var xml: String = FileAccess.get_file_as_string(
			xml_dir.get_current_dir().path_join(file_name)
		)
		var found: RegExMatch = name_pattern.search(xml)
		if found == null:
			continue
		var doc_name: String = found.get_string(1).xml_unescape()
		var path: String = _script_path(doc_name, class_paths)
		if path.is_empty() or _excluded(path, exclude):
			continue
		classes.append({"name": doc_name, "path": path, "xml": xml})
		if fallback and _is_top_level(doc_name):
			comments.merge(scan_comments(FileAccess.get_file_as_string(path), doc_name))

	var version: Dictionary = Engine.get_version_info()
	var docs_version: String = "latest"
	if version["status"] == "stable":
		docs_version = "%d.%d" % [version["major"], version["minor"]]

	return {
		"project": {
			"name": String(ProjectSettings.get_setting("application/config/name", "")),
			"description": String(
				ProjectSettings.get_setting("application/config/description", "")
			),
			"version": String(ProjectSettings.get_setting("application/config/version", "")),
			"main_scene": ResourceUID.ensure_path(
				String(ProjectSettings.get_setting("application/run/main_scene", ""))
			),
			"godot": String(version["string"]),
			"built": Time.get_datetime_string_from_system(false, true),
			"output": output_path(),
			"engine_docs": "https://docs.godotengine.org/en/%s/classes/" % docs_version,
		},
		"classes": classes,
		"comments": comments,
		"parents": parents,
		"script_classes": class_paths,
		"usage": _usage(exclude),
		"autoloads": autoloads,
		"input": _input_actions(),
		"guides": _guides(),
	}


static func write(data: Dictionary) -> Error:
	var page: String = FileAccess.get_file_as_string(WEB_DIR.path_join("template.html"))
	if not page.contains(PLACEHOLDER):
		push_error("GDDocs: %stemplate.html is missing or has no %s" % [WEB_DIR, PLACEHOLDER])
		return ERR_FILE_CORRUPT

	# Every < is escaped so doc text containing </script> cannot end the data block early.
	var scripts: String = "<script>%s</script>\n<script>window.GDDOCS = %s;</script>\n" \
		+ "<script>%s</script>"
	scripts = scripts % [
		FileAccess.get_file_as_string(WEB_DIR.path_join("marked.umd.js")),
		JSON.stringify(data).replace("<", "\\u003c"),
		FileAccess.get_file_as_string(WEB_DIR.path_join("gddocs.js")),
	]

	var output: String = output_path()
	var error: Error = DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	if error != OK:
		push_error("GDDocs: cannot create %s (%s)" % [output.get_base_dir(), error_string(error)])
		return error
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		error = FileAccess.get_open_error()
		push_error("GDDocs: cannot write %s (%s)" % [output, error_string(error)])
		return error
	file.store_string(page.replace(PLACEHOLDER, scripts))
	return OK


# Keys are "" for the class, then "method/x", "member/x"...; ponytail: one inner class level only
static func scan_comments(source: String, doc_name: String) -> Dictionary:
	var declaration: RegEx = RegEx.create_from_string(
		"^([ \\t]*)(?:@\\w+(?:\\([^)]*\\))?\\s+)*(?:static\\s+)?" \
		+ "(func|var|const|signal|enum|class)\\s+(\\w+)"
	)
	var annotation: RegEx = RegEx.create_from_string("^@\\w+(?:\\([^)]*\\))?$")
	var found: Dictionary = {}
	var pending: PackedStringArray = []
	var inner: String = ""
	var inner_indent: int = -1
	var seen_declaration: bool = false

	for line: String in source.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("##") or stripped.begins_with("#region") \
		or stripped.begins_with("#endregion"):
			pending.clear()
		elif stripped.begins_with("#"):
			pending.append(stripped.trim_prefix("#").strip_edges())
		elif stripped.is_empty():
			if not seen_declaration and not pending.is_empty():
				_store(found, doc_name, "", pending)
			pending.clear()
		elif line.begins_with("class_name") or line.begins_with("extends"):
			_store(found, doc_name, "", pending)
			pending.clear()
		elif annotation.search(stripped) != null:
			pass
		else:
			var matched: RegExMatch = declaration.search(line)
			if matched != null:
				var indent: int = matched.get_string(1).length()
				var kind: String = matched.get_string(2)
				var member: String = matched.get_string(3)
				seen_declaration = true
				if indent == 0:
					inner = ""
					if kind == "class":
						inner = "%s.%s" % [doc_name, member]
						inner_indent = -1
						_store(found, inner, "", pending)
					else:
						_store(found, doc_name, DECLARATION_KEYS[kind] + "/" + member, pending)
				elif not inner.is_empty() and kind != "class":
					if inner_indent == -1:
						inner_indent = indent
					if indent == inner_indent:
						_store(found, inner, DECLARATION_KEYS[kind] + "/" + member, pending)
			pending.clear()
	return found


static func _store(
	found: Dictionary, target: String, key: String, lines: PackedStringArray
) -> void:
	if lines.is_empty():
		return
	if not found.has(target):
		found[target] = {}
	found[target][key] = " ".join(lines)


static func _run_doctool() -> DirAccess:
	var temp: DirAccess = DirAccess.create_temp("gddocs")
	if temp == null:
		var reason: String = error_string(DirAccess.get_open_error())
		push_error("GDDocs: cannot create a temp dir (%s)" % reason)
		return null
	var args: PackedStringArray = [
		"--headless",
		"--doctool",
		temp.get_current_dir(),
		"--gdscript-docs",
		ProjectSettings.globalize_path("res://"),
	]
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	if code != 0:
		var log_tail: String = "".join(output).right(4000)
		push_error("GDDocs: the doctool run exited with %d:\n%s" % [code, log_tail])
		return null
	return temp


# Doc names are a class_name or autoload name, a quoted "dir/file.gd", or Outer.Inner.
static func _script_path(doc_name: String, class_paths: Dictionary[String, String]) -> String:
	if doc_name.begins_with("\""):
		return "res://" + doc_name.get_slice("\"", 1)
	return String(class_paths.get(doc_name.get_slice(".", 0), ""))


static func _is_top_level(doc_name: String) -> bool:
	return doc_name.ends_with("\"") or not doc_name.contains(".")


static func _excluded(path: String, exclude: PackedStringArray) -> bool:
	for prefix: String in exclude:
		if not prefix.is_empty() and path.begins_with(prefix):
			return true
	return false


static func _setting_list(key: String, fallback: PackedStringArray) -> PackedStringArray:
	return PackedStringArray(ProjectSettings.get_setting(key, fallback))


static func _collect_files(
	dir: String, extensions: PackedStringArray, exclude: PackedStringArray, into: PackedStringArray
) -> void:
	if _excluded(dir.path_join(""), exclude):
		return
	for sub: String in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_collect_files(dir.path_join(sub), extensions, exclude, into)
	for file_name: String in DirAccess.get_files_at(dir):
		if extensions.has(file_name.get_extension()):
			into.append(dir.path_join(file_name))


# Scene or resource path -> the scripts it references.
static func _usage(exclude: PackedStringArray) -> Dictionary:
	var files: PackedStringArray = []
	_collect_files("res://", USAGE_EXTENSIONS, exclude, files)
	var usage: Dictionary = {}
	for file_path: String in files:
		var scripts: PackedStringArray = []
		for dependency: String in ResourceLoader.get_dependencies(file_path):
			var parts: PackedStringArray = dependency.split("::")
			var path: String = parts[parts.size() - 1]
			if parts.size() == 3 and parts[0].begins_with("uid://"):
				var from_uid: String = ResourceUID.ensure_path(parts[0])
				if not from_uid.is_empty():
					path = from_uid
			if path.get_extension() == "gd":
				scripts.append(path)
		if not scripts.is_empty():
			usage[file_path] = scripts
	return usage


static func _autoloads() -> Array[Dictionary]:
	var autoloads: Array[Dictionary] = []
	for key: String in _settings_under("autoload/"):
		var value: String = String(ProjectSettings.get_setting(key))
		autoloads.append({
			"name": key.trim_prefix("autoload/"),
			"path": ResourceUID.ensure_path(value.trim_prefix("*")),
			"global": value.begins_with("*"),
		})
	return autoloads


static func _input_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for key: String in _settings_under("input/"):
		var action: Dictionary = ProjectSettings.get_setting(key)
		var events: PackedStringArray = []
		for event: InputEvent in action.get("events", []):
			if event != null:
				events.append(event.as_text())
		var action_name: String = key.trim_prefix("input/")
		actions.append({
			"name": action_name,
			"deadzone": float(action.get("deadzone", 0.5)),
			"events": events,
			"builtin": action_name.begins_with("ui_"),
		})
	return actions


# Guides ignore the exclude list, since naming a folder here is already a choice.
static func _guides() -> Array[Dictionary]:
	var paths: PackedStringArray = []
	for entry: String in _setting_list(SETTING_GUIDES, DEFAULT_GUIDES):
		if entry.get_extension() == "md":
			if FileAccess.file_exists(entry):
				paths.append(entry)
		elif DirAccess.dir_exists_absolute(entry):
			_collect_files(entry, ["md"], [], paths)
	var guides: Array[Dictionary] = []
	for path: String in paths:
		guides.append({"path": path, "markdown": FileAccess.get_file_as_string(path)})
	return guides


static func _settings_under(prefix: String) -> PackedStringArray:
	var keys: PackedStringArray = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var key: String = String(property["name"])
		if key.begins_with(prefix):
			keys.append(key)
	return keys
