extends Node
const MAIN: PackedScene = preload("res://game/main.tscn")
var _main: Main
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = "127.0.0.1"
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	WowClient.session.state_changed.connect(func(state: int, message: String) -> void: print("STATE ", state, " ", message))
	get_tree().create_timer(40.0).timeout.connect(get_tree().quit)
