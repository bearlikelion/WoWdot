@tool
class_name FullscreenExport
extends EditorPlugin

## Plugin that automatically sets window mode to fullscreen during export,
## reverting to previous mode once export completes.

# https://docs.godotengine.org/en/4.5/classes/class_displayserver.html#enumerations
const WINDOW_MODE_SETTING: String = "display/window/size/mode"
const WINDOW_MODE_PREVIOUS: int = 0
const WINDOW_MODE_FULLSCREEN: int = 4 # 3 = Fullscreen | 4 = Exclusive Fullscreen

var _exporter: FullscreenExporterPlugin


func _enter_tree() -> void:
	_exporter = FullscreenExporterPlugin.new()
	add_export_plugin(_exporter)


func _exit_tree() -> void:
	# Restore window mode if plugin is disabled during export
	if _exporter and _exporter._original_mode != -1:
		_exporter._restore_window_mode()

	remove_export_plugin(_exporter)


class FullscreenExporterPlugin extends EditorExportPlugin:
	var _original_mode: int = -1  # -1 means not currently exporting

	func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
		# Safety check: if we have a stored value, something went wrong in previous export
		if _original_mode != -1:
			push_warning("ExportFullscreen: Previous export didn't complete cleanly, resetting state")
			_restore_window_mode()

		# Store current window mode (defaults to 0 if not set)
		_original_mode = ProjectSettings.get_setting(WINDOW_MODE_SETTING, WINDOW_MODE_PREVIOUS)

		# Set to fullscreen for export
		ProjectSettings.set_setting(WINDOW_MODE_SETTING, WINDOW_MODE_FULLSCREEN)

		var err: Error = ProjectSettings.save()
		if err != OK:
			push_error("ExportFullscreen: Failed to save project settings. Error: %s" % error_string(err))
		else:
			print("ExportFullscreen: Set window mode to exclusive fullscreen for export (original: %d)" % _original_mode)


	func _export_end() -> void:
		_restore_window_mode()


	func _restore_window_mode() -> void:
		# Only restore if we have a stored value
		if _original_mode == -1:
			return

		# Restore original mode
		ProjectSettings.set_setting(WINDOW_MODE_SETTING, _original_mode)

		var err: Error = ProjectSettings.save()
		if err != OK:
			push_error("ExportFullscreen: Failed to restore window mode. Error: %s" % error_string(err))
		else:
			print("ExportFullscreen: Restored window mode to %d" % _original_mode)

		# Reset state
		_original_mode = -1
