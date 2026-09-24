class_name VideoSettings
extends RefCounted

signal changed

const SETTINGS_PATH: String = "user://video.cfg"
const SECTION: String = "video"
const OPTIONS: Array[StringName] = [
	&"windowed", &"maximized", &"vsync", &"shadows", &"volumetric_fog",
]

# Windowed and maximized is a borderless window over the whole screen, as the stock option says.
var windowed: bool = true
var maximized: bool = false
var vsync: bool = false
var shadows: bool = false
var volumetric_fog: bool = false
# Zero leaves the window as it is and renders fullscreen at the screen's own size.
var resolution: Vector2i = Vector2i.ZERO


# Starts from the saved choices, or from the window as the project opened it when none are saved.
func _init() -> void:
	var current: Dictionary = defaults()
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	current[&"windowed"] = mode != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	current[&"maximized"] = mode == DisplayServer.WINDOW_MODE_FULLSCREEN
	var saved: ConfigFile = ConfigFile.new()
	var has_saved: bool = saved.load(SETTINGS_PATH) == OK
	for option: StringName in OPTIONS:
		var value: bool = current[option]
		set(option, saved.get_value(SECTION, option, value) if has_saved else value)
	if has_saved:
		resolution = saved.get_value(SECTION, "resolution", Vector2i.ZERO)


# The project's own window settings, which the fullscreen export plugin sets for exported builds.
static func defaults() -> Dictionary:
	var mode: int = ProjectSettings.get_setting("display/window/size/mode", 0)
	return {
		&"windowed": mode != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
		&"maximized": mode == DisplayServer.WINDOW_MODE_FULLSCREEN,
		&"vsync": ProjectSettings.get_setting("display/window/vsync/vsync_mode", 0) != 0,
		&"shadows": false,
		&"volumetric_fog": false,
		&"resolution": Vector2i.ZERO,
	}


func apply() -> void:
	if DisplayServer.get_name() != "headless":
		var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if windowed:
			mode = DisplayServer.WINDOW_MODE_FULLSCREEN if maximized \
			else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
		var sync: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED if vsync \
		else DisplayServer.VSYNC_DISABLED
		DisplayServer.window_set_vsync_mode(sync)
		_apply_resolution(mode)
	changed.emit()


func save() -> void:
	var saved: ConfigFile = ConfigFile.new()
	for option: StringName in OPTIONS:
		saved.set_value(SECTION, option, get(option))
	saved.set_value(SECTION, "resolution", resolution)
	saved.save(SETTINGS_PATH)


# A window takes the size itself; a full screen keeps its mode and renders the world smaller.
func _apply_resolution(mode: DisplayServer.WindowMode) -> void:
	var screen: Vector2i = DisplayServer.screen_get_size()
	var scale: float = 1.0
	if resolution != Vector2i.ZERO and mode == DisplayServer.WINDOW_MODE_WINDOWED:
		var size: Vector2i = resolution.min(screen)
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(DisplayServer.screen_get_position() + (screen - size) / 2)
	elif resolution != Vector2i.ZERO:
		scale = minf(float(resolution.x) / screen.x, float(resolution.y) / screen.y)
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	root.scaling_3d_scale = scale
