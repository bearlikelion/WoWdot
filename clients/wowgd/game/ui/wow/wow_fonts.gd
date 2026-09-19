class_name WowFonts
extends RefCounted

const THEME: Theme = preload("res://game/ui/wow/fonts.tres")
const HUD_THEME: Theme = preload("res://game/ui/hud_theme.tres")
const DEFAULT_FONT: String = "Fonts\\FRIZQT__.TTF"

static var _fonts: Dictionary[String, FontFile] = {}


# The generated theme names each variation's font file; the files stay in the archive.
static func apply() -> void:
	var fonts: Theme = THEME
	fonts.default_font = font(DEFAULT_FONT)
	for theme: Theme in [THEME, HUD_THEME]:
		var files: Dictionary = theme.get_meta("wow_fonts", {})
		for variation: String in files:
			theme.set_font("font", variation, font(files[variation]))


static func font(file: String) -> FontFile:
	if not _fonts.has(file):
		var loaded: FontFile = FontFile.new()
		loaded.data = WowLoader.get_shared().archive.read(file)
		_fonts[file] = loaded
	return _fonts[file]
