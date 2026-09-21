class_name StackSplitCheck
extends Control

var _failures: PackedStringArray = []
var _taken: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://ui/stack_split_frame.tscn")
	var frame: StackSplitFrame = scene.instantiate()
	add_child(frame)
	frame.accepted.connect(func(count: int) -> void: _taken = count)
	frame.open(5, Vector2(200.0, 200.0))
	var left: BaseButton = frame.get_node("%StackSplitLeftButton")
	var right: BaseButton = frame.get_node("%StackSplitRightButton")
	_check(left.disabled and not right.disabled, "it opens on one, which cannot go lower")
	for i: int in 10:
		right.pressed.emit()
	_check((frame.get_node("%StackSplitText") as Label).text == "4", "the count stops one short")
	_check(right.disabled, "and the right arrow greys out there")
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png("user://stack_split_check.png")
	(frame.get_node("%StackSplitOkayButton") as BaseButton).pressed.emit()
	_check(_taken == 4 and not frame.visible, "okay hands the count over and closes")
	if _failures.is_empty():
		print("stack_split_check: OK")
	else:
		for line: String in _failures:
			print("  ", line)
		print("stack_split_check: FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)
