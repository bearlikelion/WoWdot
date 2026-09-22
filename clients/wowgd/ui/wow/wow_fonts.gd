class_name WowFonts
extends RefCounted

const THEME: Theme = preload("res://ui/fonts.tres")
const HUD_THEME: Theme = preload("res://ui/hud_theme.tres")
const DEFAULT_FONT: String = "Fonts\\FRIZQT__.TTF"

static var _fonts: Dictionary[String, FontFile] = {}
static var _applied: bool = false


# Fonts come from the archive; each theme edit notifies every Control, so edit once, quietly.
static func apply() -> void:
	if _applied:
		return
	_applied = true
	for theme: Theme in [THEME, HUD_THEME]:
		theme.set_block_signals(true)
	var fonts: Theme = THEME
	fonts.default_font = font(DEFAULT_FONT)
	for theme: Theme in [THEME, HUD_THEME]:
		var files: Dictionary = theme.get_meta("wow_fonts", {})
		for variation: String in files:
			theme.set_font("font", variation, font(files[variation]))
			_add_rich_variation(theme, variation)
	for theme: Theme in [THEME, HUD_THEME]:
		theme.set_block_signals(false)
		theme.emit_changed()


static func font(file: String) -> FontFile:
	if not _fonts.has(file):
		var loaded: FontFile = FontFile.new()
		loaded.data = WowLoader.get_shared().archive.read(file)
		_fonts[file] = loaded
	return _fonts[file]


# RichTextLabels read other theme items than Labels, so each font also gets a <name>Rich twin.
static func _add_rich_variation(theme: Theme, variation: String) -> void:
	var rich: StringName = StringName(variation + "Rich")
	theme.set_type_variation(rich, &"RichTextLabel")
	theme.set_font("normal_font", rich, theme.get_font("font", variation))
	# The default box pads every label, which shows as a gap between stacked chat messages.
	theme.set_stylebox("normal", rich, StyleBoxEmpty.new())
	if theme.has_font_size("font_size", variation):
		theme.set_font_size("normal_font_size", rich, theme.get_font_size("font_size", variation))
	for colors: PackedStringArray in [
		PackedStringArray(["font_color", "default_color"]),
		PackedStringArray(["font_shadow_color", "font_shadow_color"]),
		PackedStringArray(["font_outline_color", "font_outline_color"]),
	]:
		if theme.has_color(colors[0], variation):
			theme.set_color(colors[1], rich, theme.get_color(colors[0], variation))
	for constant: String in ["shadow_offset_x", "shadow_offset_y", "outline_size"]:
		if theme.has_constant(constant, variation):
			theme.set_constant(constant, rich, theme.get_constant(constant, variation))
