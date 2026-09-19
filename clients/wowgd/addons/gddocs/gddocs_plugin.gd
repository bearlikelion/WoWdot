@tool
class_name GDDocsPlugin
extends EditorPlugin

const MENU_ITEM: String = "Build GDDocs"

var _thread: Thread = null


func _enter_tree() -> void:
	_declare_settings()
	add_tool_menu_item(MENU_ITEM, _on_build_requested)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM)
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func _on_build_requested() -> void:
	if _thread != null:
		return
	EditorInterface.get_editor_toaster().push_toast("GDDocs: building...")
	_thread = Thread.new()
	_thread.start(_build_on_thread)


# Runs on the worker thread; the doctool subprocess takes a few seconds on large projects.
func _build_on_thread() -> void:
	_on_build_finished.call_deferred(GDDocsBuilder.build())


func _on_build_finished(error: Error) -> void:
	_thread.wait_to_finish()
	_thread = null
	var toaster: EditorToaster = EditorInterface.get_editor_toaster()
	if error != OK:
		toaster.push_toast(
			"GDDocs: build failed (%s), see Output" % error_string(error),
			EditorToaster.SEVERITY_ERROR
		)
		return
	var output: String = GDDocsBuilder.output_path()
	toaster.push_toast("GDDocs: wrote %s" % output)
	OS.shell_open(ProjectSettings.globalize_path(output))


func _declare_settings() -> void:
	var added: bool = false
	added = _declare(GDDocsBuilder.SETTING_OUTPUT, GDDocsBuilder.DEFAULT_OUTPUT, {
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_SAVE_FILE,
		"hint_string": "*.html",
	}) or added
	added = _declare(GDDocsBuilder.SETTING_EXCLUDE, GDDocsBuilder.DEFAULT_EXCLUDE, {
		"type": TYPE_PACKED_STRING_ARRAY,
		"hint": PROPERTY_HINT_TYPE_STRING,
		"hint_string": "%d/%d:" % [TYPE_STRING, PROPERTY_HINT_DIR],
	}) or added
	added = _declare(GDDocsBuilder.SETTING_GUIDES, GDDocsBuilder.DEFAULT_GUIDES, {
		"type": TYPE_PACKED_STRING_ARRAY,
	}) or added
	added = _declare(GDDocsBuilder.SETTING_FALLBACK, true, {
		"type": TYPE_BOOL,
	}) or added
	if added:
		ProjectSettings.save()


# True when the setting was missing, so the caller knows to write project.godot.
func _declare(key: String, default: Variant, info: Dictionary) -> bool:
	var added: bool = not ProjectSettings.has_setting(key)
	if added:
		ProjectSettings.set_setting(key, default)
	ProjectSettings.set_initial_value(key, default)
	var property: Dictionary = info.duplicate()
	property["name"] = key
	ProjectSettings.add_property_info(property)
	ProjectSettings.set_as_basic(key, true)
	return added
