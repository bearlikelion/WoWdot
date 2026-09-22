class_name WaterFx
extends Node3D

signal splashed

# A wake trails a player wading at least this deep, and a splash marks stepping into water.
const WADE_DEPTH: float = 0.3
const WADE_SPEED: float = 1.0

@export var player: Player

var _wet: bool = false

@onready var _wake: GPUParticles3D = %Wake
@onready var _splash: GPUParticles3D = %Splash


func _process(_delta: float) -> void:
	if player == null:
		return
	var surface: float = player.water_surface()
	var depth: float = surface - player.global_position.y if not is_nan(surface) else -1.0
	var wet: bool = depth > WADE_DEPTH
	global_position = Vector3(player.global_position.x, surface, player.global_position.z) \
	if wet else player.global_position
	var moving: bool = Vector2(player.velocity.x, player.velocity.z).length() > WADE_SPEED
	_wake.emitting = wet and moving
	if wet and not _wet and player.velocity.y < 0.0:
		_splash.restart()
		splashed.emit()
	_wet = wet
