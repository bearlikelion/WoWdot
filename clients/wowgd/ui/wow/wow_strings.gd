class_name WowStrings
extends RefCounted

# Game strings first; the login screens' own strings fill in the keys they lack.
const STRING_FILES: PackedStringArray = [
	"Interface\\FrameXML\\GlobalStrings.lua",
	"Interface\\GlueXML\\GlueStrings.lua",
	# The EMOTEn_TOKEN names each text emote's slash command belongs to.
	"Interface\\FrameXML\\ChatFrame.lua",
]

static var _strings: Dictionary[String, String] = {}


# The stock interface's text, read from the archive's string files the first time it is asked.
static func get_text(key: String, fallback: String = "") -> String:
	if _strings.is_empty():
		_load()
	return _strings.get(key, fallback if not fallback.is_empty() else key)


static func has_text(key: String) -> bool:
	if _strings.is_empty():
		_load()
	return _strings.has(key)


# Lua's string.format: %s and %d in order, %2$s by position, arguments left over ignored.
static func format(template: String, args: Array) -> String:
	var out: String = ""
	var next: int = 0
	var from: int = 0
	var pattern: RegEx = RegEx.create_from_string("%(?:(\\d+)\\$)?(\\d*)([sd])")
	for found: RegExMatch in pattern.search_all(template):
		var at: int = found.get_string(1).to_int() - 1 if not found.get_string(1).is_empty() else next
		next += 1
		out += template.substr(from, found.get_start() - from)
		if at < args.size():
			# A width such as the 02 in SHORTDATE's %1$02d pads a number with zeros.
			var width: String = found.get_string(2)
			out += ("%" + width + "d") % int(args[at]) if found.get_string(3) == "d" and width \
					else str(args[at])
		from = found.get_end()
	return _plurals(out + template.substr(from))


# Drops the |cAARRGGBB and |r colour escapes for text shown in a plain label.
# SecondsToTime: the two largest of days, hours, minutes and seconds, as "5 Mins 12 Secs ".
static func seconds_to_time(seconds: int) -> String:
	var out: String = ""
	var count: int = 0
	for unit: Array in [[86400, "DAYS_ABBR"], [3600, "HOURS_ABBR"], [60, "MINUTES_ABBR"]]:
		if count < 2 and seconds >= unit[0] and (unit[0] == 60 or seconds > unit[0]):
			var amount: int = floori(seconds / float(unit[0]))
			out += "%d %s " % [amount, get_text(unit[1] + ("" if amount == 1 else "_P1"))]
			seconds %= unit[0]
			count += 1
	if count < 2 and seconds > 0:
		out += "%d %s " % [seconds, get_text("SECONDS_ABBR" + ("" if seconds == 1 else "_P1"))]
	return out


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


# Lua escapes the strings use: \" and \n, decimal bytes such as \32 for a trailing space, and
# WoW's own |n line break, which a plain label would otherwise show as text.
static func _unescape(text: String) -> String:
	var decimal: RegEx = RegEx.create_from_string("\\\\(\\d{1,3})")
	var out: String = ""
	var at: int = 0
	for found: RegExMatch in decimal.search_all(text):
		out += text.substr(at, found.get_start() - at) + char(found.get_string(1).to_int())
		at = found.get_end()
	out += text.substr(at)
	return out.replace('\\"', '"').replace("\\n", "\n").replace("|n", "\n")


# The |4singular:plural; grammar, which picks by the number just before it.
static func _plurals(text: String) -> String:
	var out: String = text
	var pattern: RegEx = RegEx.create_from_string("(\\d+)(\\s*)\\|4([^:;]*):([^;]*);")
	for found: RegExMatch in pattern.search_all(text):
		var word: String = found.get_string(3 if found.get_string(1) == "1" else 4)
		out = out.replace(found.get_string(), found.get_string(1) + found.get_string(2) + word)
	return out
