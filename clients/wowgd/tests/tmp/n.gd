extends Node
const MAIN: PackedScene = preload("res://game/main.tscn")
var _main: Main
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	_run.call_deferred()
func _run() -> void:
	while _main.world == null or not _main.world.player().active:
		await get_tree().process_frame
	var plates: NamePlates = _main.world.find_child("NamePlates", true, false)
	plates.show_enemies = true
	plates.show_friends = true
	await get_tree().create_timer(10.0).timeout
	print("PLATES ", plates.get_child_count())
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT"))
	get_tree().quit()
