class_name HelpCheck
extends Control

var _failures: PackedStringArray = []
var _filed: Array = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://ui/help_frame.tscn")
	var frame: HelpFrame = scene.instantiate()
	add_child(frame)
	frame.ticket_requested.connect(func(text: String, category: int) -> void:
		_filed = [text, category]
	)
	frame.show()
	_check((frame.get_node("%HelpFrameHome") as Control).visible, "the window opens on its home page")
	(frame.get_node("%HelpFrameHomeIssues") as BaseButton).pressed.emit()
	var first: Label = frame.get_node("%HelpFrameButton1Text")
	_check(not first.text.is_empty(), "categories come from GMTicketCategory.dbc")
	(frame.get_node("%HelpFrameButton2") as BaseButton).pressed.emit()
	_check((frame.get_node("%HelpFrameOpenTicket") as Control).visible, "a category opens the editor")
	(frame.get_node("%HelpFrameOpenTicketText") as TextEdit).text = "stuck in a wall"
	(frame.get_node("%HelpFrameOpenTicketSubmit") as BaseButton).pressed.emit()
	_check(_filed.size() == 2 and _filed[0] == "stuck in a wall", "submit files the text")
	_check(_filed.size() == 2 and _filed[1] > 0, "under the category picked")

	var open: PackedByteArray = [6, 0, 0, 0]
	open.append_array("old text".to_utf8_buffer())
	open.append_array([0, 3])
	WowClient.session.packet_received.emit("SMSG_GMTICKET_GETTICKET", open)
	var submit: Label = frame.get_node("%HelpFrameOpenTicketSubmitText")
	_check(submit.text == WowStrings.get_text("EDIT_TICKET"), "an open ticket turns submit into edit")
	var text: TextEdit = frame.get_node("%HelpFrameOpenTicketText")
	_check(text.text == "old text", "and loads its text")
	if _failures.is_empty():
		print("help_check: OK")
	else:
		for line: String in _failures:
			print("  ", line)
		print("help_check: FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)
