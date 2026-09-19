class_name WowStrings
extends RefCounted

# Game strings first; the login screens' own strings fill in the keys they lack.
const STRING_FILES: PackedStringArray = [
	"Interface\\FrameXML\\GlobalStrings.lua",
	"Interface\\GlueXML\\GlueStrings.lua",
]

static var _strings: Dictionary[String, String] = {}


# The stock interface's text, read from the archive's string files the first time it is asked.
static func get_text(key: String, fallback: String = "") -> String:
	if _strings.is_empty():
		_load()
	return _strings.get(key, fallback if not fallback.is_empty() else key)


# Drops the |cAARRGGBB and |r colour escapes for text shown in a plain label.
static func strip_colors(text: String) -> String:
	return RegEx.create_from_string("\\|c[0-9a-fA-F]{8}|\\|r").sub(text, "", true)


# Chat's |cAARRGGBB colours, |r, |H...|h[text]|h links and |n as RichTextLabel BBCode.
static func to_bbcode(text: String) -> String:
	var out: String = ""
	var colors: int = 0
	var i: int = 0
	while i < text.length():
		var c: String = text[i]
		var next: String = text[i + 1] if i + 1 < text.length() else ""
		if c == "|" and next == "c" and i + 10 <= text.length():
			out += "[color=#%s]" % text.substr(i + 4, 6)
			colors += 1
			i += 10
		elif c == "|" and next == "r":
			if colors > 0:
				out += "[/color]"
				colors -= 1
			i += 2
		elif c == "|" and next == "H":
			var link_end: int = text.find("|h", i + 2)
			var text_end: int = text.find("|h", link_end + 2) if link_end >= 0 else -1
			if text_end < 0:
				out += _escape_bbcode(text.substr(i))
				break
			out += "[url=%s]%s[/url]" % [
				text.substr(i + 2, link_end - i - 2),
				_escape_bbcode(text.substr(link_end + 2, text_end - link_end - 2)),
			]
			i = text_end + 2
		elif c == "|" and next == "n":
			out += "\n"
			i += 2
		elif c == "|" and next == "|":
			out += "|"
			i += 2
		else:
			out += _escape_bbcode(c)
			i += 1
	for j: int in colors:
		out += "[/color]"
	return out


static func _escape_bbcode(text: String) -> String:
	var out: String = ""
	for c: String in text:
		out += "[lb]" if c == "[" else "[rb]" if c == "]" else c
	return out


static func _load() -> void:
	var line: RegEx = RegEx.create_from_string('(?m)^(\\w+)\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)";')
	for file: String in STRING_FILES:
		var source: String = WowLoader.get_shared().archive.read(file).get_string_from_utf8()
		for found: RegExMatch in line.search_all(source):
			if not _strings.has(found.get_string(1)):
				_strings[found.get_string(1)] = _unescape(found.get_string(2))


# Lua escapes the strings use: \" and \n, and decimal bytes such as \32 for a trailing space.
static func _unescape(text: String) -> String:
	var decimal: RegEx = RegEx.create_from_string("\\\\(\\d{1,3})")
	var out: String = ""
	var at: int = 0
	for found: RegExMatch in decimal.search_all(text):
		out += text.substr(at, found.get_start() - at) + char(found.get_string(1).to_int())
		at = found.get_end()
	out += text.substr(at)
	return out.replace('\\"', '"').replace("\\n", "\n")
