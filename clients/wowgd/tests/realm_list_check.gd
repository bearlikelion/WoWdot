class_name RealmListCheck
extends Node

const REALM_LIST: PackedScene = preload("res://ui/realm_list.tscn")
const REALMS: int = 25
const SCROLL_TO: int = 7

var _failures: PackedStringArray = []


# A logon server with more realms than rows has to scroll, which no local server can show.
func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var list: RealmList = REALM_LIST.instantiate()
	add_child(list)
	await get_tree().process_frame
	var realms: Array = []
	for i: int in REALMS:
		realms.append({
			"name": "Realm %d" % i, "flags": 0, "characters": 0, "icon": 0, "population": 1.0,
		})
	list.open(realms, "")
	await get_tree().process_frame
	var scroll: WowScrollFrame = list.get_node("%RealmListScrollFrame")
	_check(scroll.visible, "a long list shows its scroll bar")
	_check(_row_text(list, 0) == "Realm 0", "the top row is the first realm")
	scroll.scroll_to(SCROLL_TO)
	await get_tree().process_frame
	_check(
		_row_text(list, 0) == "Realm %d" % SCROLL_TO,
		"scrolling moves the rows (%s)" % _row_text(list, 0),
	)
	_check(
		_row_text(list, RealmList.ROWS - 1) == "Realm %d" % (SCROLL_TO + RealmList.ROWS - 1),
		"the bottom row follows too",
	)
	(list.get_node("%RealmListRealmButton1") as BaseButton).pressed.emit()
	await get_tree().process_frame
	_check(list.get("_selected") == SCROLL_TO, "picking a scrolled row picks that realm")
	list.open(realms.slice(0, 4), "")
	await get_tree().process_frame
	_check(not scroll.visible, "a short list hides the scroll bar")
	if _failures.is_empty():
		print("realm_list_check: OK")
	else:
		for line: String in _failures:
			print("  ", line)
		print("realm_list_check: FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _row_text(list: RealmList, row: int) -> String:
	var button: Control = list.get_node("%%RealmListRealmButton%d" % (row + 1))
	return (button.get_node("%%RealmListRealmButton%dNormalText" % (row + 1)) as Label).text


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)
