class_name Emotes
extends RefCounted

# EmotesText: the slash token, the Emotes row that animates it, then EmotesTextData ids.
enum Column { NAME = 1, EMOTE = 2, WITH_TARGET = 3, AT_YOU = 4, YOU_AT_TARGET = 5, ALONE = 7,
	YOU_ALONE = 9 }

static var _texts: WowDBC
static var _text_data: WowDBC
static var _emotes: WowDBC
static var _animations: WowDBC
static var _by_token: Dictionary[String, int] = {}


# The text emote a slash command names, or 0 when it names none.
static func find(token: String) -> int:
	_load()
	return _by_token.get(token.to_upper(), 0)


static func emote_of(text_emote: int) -> int:
	_load()
	var row: int = _texts.find(text_emote)
	return _texts.get_uint(row, Column.EMOTE) if row >= 0 else 0


static func animation(emote_id: int) -> String:
	_load()
	var row: int = _emotes.find(emote_id)
	if row < 0:
		return ""
	var anim: int = _emotes.get_uint(row, 2)
	var anim_row: int = _animations.find(anim)
	return _animations.get_string(anim_row, 1) if anim_row >= 0 else ""


# EmoteChatBuilder's line, which reads differently for the actor, the target and everyone else.
static func message(text_emote: int, actor: String, target: String, mine: bool, at_me: bool
) -> String:
	_load()
	var row: int = _texts.find(text_emote)
	if row < 0:
		return ""
	var column: Column = Column.ALONE
	if target.is_empty():
		column = Column.YOU_ALONE if mine else Column.ALONE
	elif mine:
		column = Column.YOU_AT_TARGET
	elif at_me:
		column = Column.AT_YOU
	else:
		column = Column.WITH_TARGET
	var text: String = _text(_texts.get_uint(row, column))
	if text.is_empty():
		column = Column.ALONE
		text = _text(_texts.get_uint(row, column))
	var names: Array[String] = [actor, target]
	if column == Column.AT_YOU or column == Column.ALONE:
		names = [actor]
	elif column == Column.YOU_AT_TARGET:
		names = [target]
	elif column == Column.YOU_ALONE:
		names = []
	return text % names if text.count("%s") == names.size() else text


static func _text(text_id: int) -> String:
	if text_id == 0:
		return ""
	var row: int = _text_data.find(text_id)
	return _text_data.get_string(row, 1) if row >= 0 else ""


static func _load() -> void:
	if _texts != null:
		return
	var archive: WowArchive = WowAssets.archive
	_texts = WowDBC.open(archive, "EmotesText")
	_text_data = WowDBC.open(archive, "EmotesTextData")
	_emotes = WowDBC.open(archive, "Emotes")
	_animations = WowDBC.open(archive, "AnimationData")
	for row: int in _texts.row_count():
		_by_token[_texts.get_string(row, Column.NAME)] = _texts.get_uint(row, 0)
