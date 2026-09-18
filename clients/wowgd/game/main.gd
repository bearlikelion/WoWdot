class_name Main
extends Node

signal world_ready(world: World)

const WORLD: PackedScene = preload("res://game/world/world.tscn")

## Filled from `-- --account=... --password=... --character=...` for scripted logins.
@export var auto_account: String = ""
@export var auto_password: String = ""
@export var auto_character: String = ""

var world: World

@onready var _login: LoginScreen = %LoginScreen
@onready var _characters: CharacterSelect = %CharacterSelect


func _ready() -> void:
	_read_command_line()
	_login.realm_joined.connect(_on_realm_joined)
	_characters.character_chosen.connect(_on_character_chosen)
	WowClient.session.world_entered.connect(_on_world_entered)
	if not auto_account.is_empty():
		_characters.preferred_name = auto_character
		_login.fill_credentials(auto_account, auto_password)
		_login.log_in()


func _read_command_line() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		if parts.size() < 2:
			continue
		match parts[0]:
			"account":
				auto_account = parts[1]
			"password":
				auto_password = parts[1]
			"character":
				auto_character = parts[1]


func _on_realm_joined() -> void:
	_login.hide()
	_characters.show()
	if world:
		world.queue_free()
		world = null


func _on_character_chosen(guid: int) -> void:
	WowClient.session.enter_world(guid)


func _on_world_entered(map_id: int, position: Vector3, orientation: float) -> void:
	_characters.hide()
	if world == null:
		world = WORLD.instantiate()
		add_child(world)
		world.player_ready.connect(_on_player_ready)
	world.enter(map_id, position, orientation)


func _on_player_ready() -> void:
	world_ready.emit(world)
