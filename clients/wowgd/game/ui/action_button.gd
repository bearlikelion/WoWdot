@tool
class_name ActionButton
extends WowButton

signal used(slot: int)

enum ActionType { SPELL = 0x00, MACRO = 0x40, ITEM = 0x80 }

const ACTION_MASK: int = 0xFFFFFF
const SPELL_ATTACK: int = 6603
# ActionButton_UpdateUsable's tint for an item action with none left in the bags.
const UNUSABLE_TINT: Color = Color(0.4, 0.4, 0.4)

var slot: int = -1:
	set(value):
		slot = value
		refresh()
# Set by the stance bar, whose buttons show a spell instead of an action slot.
var stance_spell: int = 0:
	set(value):
		stance_spell = value
		refresh()
# Set by the pet bar for its command buttons, which show a fixed icon instead of a spell.
var command_icon: String = "":
	set(value):
		command_icon = value
		refresh()
var stance_active: bool = false:
	set(value):
		stance_active = value
		_update_checked()
var hotkey: String = "":
	set(value):
		hotkey = value
		if is_node_ready():
			_hotkey.text = value

var _casting_spell: int = 0
var _attacking: bool = false

@onready var _icon: TextureRect = %Icon
@onready var _count: Label = %Count
@onready var _hotkey: Label = %HotKey
@onready var _normal: TextureRect = %NormalTexture
@onready var _cooldown: WowCooldown = %Cooldown


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
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
	session.item_info_received.connect(_on_inventory_changed)
	session.object_updated.connect(_on_inventory_changed)
	WowClient.cooldowns.changed.connect(_update_cooldown)
	_hotkey.text = hotkey
	refresh()


# PickupAction: dragging an action lifts it off the bar, and dropping it places it.
func _get_drag_data(_at_position: Vector2) -> Variant:
	var carried: int = spell()
	if Engine.is_editor_hint() or carried == 0:
		return null
	var preview: TextureRect = TextureRect.new()
	preview.texture = _action_icon(carried)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = size
	set_drag_preview(preview)
	WowClient.session.set_action_button(slot, 0)
	return {"spell": carried}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return not Engine.is_editor_hint() and slot >= 0 and data is Dictionary and data.has("spell")


# A spell action packs the spell id with type 0 in the high byte.
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	WowClient.session.set_action_button(slot, data["spell"])


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
	var item_entry: int = _item()
	_icon.self_modulate = Color.WHITE
	_count.text = ""
	if not command_icon.is_empty():
		var icon: WowTexture = WowTexture.new()
		icon.file = command_icon
		_icon.texture = icon
		_icon.visible = true
		_normal.self_modulate.a = 1.0
	elif spell() != 0:
		_icon.texture = _action_icon(spell())
	elif item_entry != 0:
		var count: int = Inventory.item_count(item_entry)
		_icon.texture = Inventory.icon(item_entry)
		_icon.self_modulate = Color.WHITE if count > 0 else UNUSABLE_TINT
		_count.text = str(count) if count != 1 else ""
	_update_checked()
	_update_cooldown()


# GetActionTexture: Attack wears the main hand weapon's icon, and its own only when unarmed.
func _action_icon(spell_id: int) -> Texture2D:
	if spell_id == SPELL_ATTACK:
		var weapon: int = Inventory.entry(Inventory.equipped(Inventory.Slot.MAIN_HAND))
		var weapon_icon: Texture2D = Inventory.icon(weapon) if weapon else null
		if weapon_icon:
			return weapon_icon
	return WowAssets.spells.icon(spell_id)


func _item() -> int:
	var packed: int = _packed()
	return packed & ACTION_MASK if packed != 0 and _type(packed) == ActionType.ITEM else 0


func _packed() -> int:
	if stance_spell != 0:
		return stance_spell
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
	checked = stance_active \
	or (current != 0 and (current == _casting_spell or (current == SPELL_ATTACK and _attacking)))


func _on_mouse_entered() -> void:
	if GameTooltip.current == null:
		return
	if spell() != 0:
		GameTooltip.current.set_spell(self, spell())
	elif _item() != 0:
		GameTooltip.current.set_item(self, _item(), 0, GameTooltip.TooltipAnchor.DEFAULT)


func _on_mouse_exited() -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(self)


func _on_spell_cast_started(caster: int, spell_id: int, _cast_time_msec: int) -> void:
	if caster == WowClient.session.get_player_guid():
		_casting_spell = spell_id
		_update_checked()


func _on_spell_cast_ended(caster: int, _spell_id: int, _targets: PackedInt64Array = []) -> void:
	if caster == WowClient.session.get_player_guid():
		_casting_spell = 0
		_update_checked()


func _on_spell_cast_failed(caster: int, spell_id: int, _reason: int) -> void:
	_on_spell_cast_ended(caster, spell_id)


func _on_attack_changed(attacker: int, _victim: int, attacking: bool) -> void:
	if attacker == WowClient.session.get_player_guid():
		_attacking = attacking
		_update_checked()


# Item queries, weapon swaps and stack changes redraw Attack and item actions.
func _on_inventory_changed(_id: int) -> void:
	if spell() == SPELL_ATTACK or _item() != 0:
		refresh()
