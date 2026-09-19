@tool
class_name ActionButton
extends WowButton

signal used(slot: int)

enum ActionType { SPELL = 0x00, MACRO = 0x40, ITEM = 0x80 }

const ACTION_MASK: int = 0xFFFFFF
const SPELL_ATTACK: int = 6603

var slot: int = -1:
	set(value):
		slot = value
		refresh()
var hotkey: String = "":
	set(value):
		hotkey = value
		if is_node_ready():
			_hotkey.text = value

var _casting_spell: int = 0
var _attacking: bool = false

@onready var _icon: TextureRect = %Icon
@onready var _hotkey: Label = %HotKey
@onready var _normal: TextureRect = %NormalTexture
@onready var _cooldown: WowCooldown = %Cooldown


func _ready() -> void:
	super()
	pressed.connect(func() -> void: used.emit(slot))
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	var session: WowSession = WowClient.session
	session.action_buttons_changed.connect(refresh)
	session.spell_cast_started.connect(_on_spell_cast_started)
	session.spell_cast_finished.connect(_on_spell_cast_ended)
	session.spell_cast_failed.connect(_on_spell_cast_failed)
	session.attack_started.connect(_on_attack_changed.bind(true))
	session.attack_stopped.connect(_on_attack_changed.bind(false))
	WowClient.cooldowns.changed.connect(_update_cooldown)
	_hotkey.text = hotkey
	refresh()


func spell() -> int:
	var packed: int = _packed()
	return packed & ACTION_MASK if packed != 0 and _type(packed) == ActionType.SPELL else 0


func refresh() -> void:
	if not is_node_ready():
		return
	var packed: int = _packed()
	_icon.visible = packed != 0
	# Empty slots let the bar art show through, as ActionButton_Update does with its grid hidden.
	_normal.self_modulate.a = 1.0 if packed != 0 else 0.0
	if spell() != 0:
		_icon.texture = WowAssets.spells.icon(spell())
	_update_checked()
	_update_cooldown()


func _packed() -> int:
	var buttons: PackedInt32Array = WowClient.session.get_action_buttons()
	return buttons[slot] if slot >= 0 and slot < buttons.size() else 0


func _type(packed: int) -> ActionType:
	return ((packed >> 24) & 0xFF) as ActionType


func _update_cooldown() -> void:
	var cooldown: Vector2i = Vector2i.ZERO
	if spell() != 0:
		cooldown = WowClient.cooldowns.get_cooldown(spell())
	if cooldown.x + cooldown.y > Time.get_ticks_msec():
		_cooldown.start(cooldown.x, cooldown.y)
	else:
		_cooldown.stop()


func _update_checked() -> void:
	var current: int = spell()
	checked = current != 0 and (current == _casting_spell or (current == SPELL_ATTACK and _attacking))


func _on_mouse_entered() -> void:
	if spell() != 0 and GameTooltip.current:
		GameTooltip.current.set_spell(self, spell())


func _on_mouse_exited() -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(self)


func _on_spell_cast_started(caster: int, spell_id: int, _cast_time_msec: int) -> void:
	if caster == WowClient.session.get_player_guid():
		_casting_spell = spell_id
		_update_checked()


func _on_spell_cast_ended(caster: int, _spell_id: int) -> void:
	if caster == WowClient.session.get_player_guid():
		_casting_spell = 0
		_update_checked()


func _on_spell_cast_failed(caster: int, spell_id: int, _reason: int) -> void:
	_on_spell_cast_ended(caster, spell_id)


func _on_attack_changed(attacker: int, _victim: int, attacking: bool) -> void:
	if attacker == WowClient.session.get_player_guid():
		_attacking = attacking
		_update_checked()
