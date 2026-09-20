class_name FloatingCombatText
extends Node3D

# DAMAGE_TEXT_FONT from Fonts.xml.
const FONT: String = "Fonts\\FRIZQT__.TTF"
const DAMAGE_TEXT: PackedScene = preload("res://game/world/floating_damage.tscn")
const RISE: float = 1.5
const DURATION: float = 1.5
const FADE_AFTER: float = 0.9

@export var entities: Entities


func _ready() -> void:
	WowClient.combat.logged.connect(_on_combat_logged)


# The engine floats what the player does to other units over their heads.
func _on_combat_logged(event: CombatEvents.CombatEvent) -> void:
	if event.source != WowClient.session.get_player_guid() or event.target == event.source:
		return
	var look: Dictionary = CombatFeedback.appearance(event)
	var at: Vector3 = entities.head_position(event.target)
	if look.is_empty() or at == Vector3.ZERO:
		return
	var label: Label3D = DAMAGE_TEXT.instantiate()
	label.font = WowFonts.font(FONT)
	label.text = look["text"]
	label.modulate = look["color"]
	label.scale = Vector3.ONE * float(look["size"])
	add_child(label)
	label.global_position = at
	var rise: Tween = label.create_tween().set_parallel()
	rise.tween_property(label, "global_position:y", at.y + RISE, DURATION)
	rise.tween_property(label, "modulate:a", 0.0, DURATION - FADE_AFTER).set_delay(FADE_AFTER)
	rise.chain().tween_callback(label.queue_free)
