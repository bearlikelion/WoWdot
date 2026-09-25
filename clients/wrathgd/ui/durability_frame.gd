class_name DurabilityFrame
extends Control

signal layout_changed

# GetInventoryAlertStatus values that INVENTORY_ALERT_COLORS gives a color.
enum Alert { NONE, DAMAGED = 3, BROKEN = 4 }

# INVENTORY_ALERT_STATUS_SLOTS: the body parts shown together, then the ones shown alone.
const BODY: Dictionary[String, Inventory.Slot] = {
	"Head": Inventory.Slot.HEAD, "Shoulders": Inventory.Slot.SHOULDER,
	"Chest": Inventory.Slot.CHEST, "Waist": Inventory.Slot.WAIST, "Legs": Inventory.Slot.LEGS,
	"Feet": Inventory.Slot.FEET, "Wrists": Inventory.Slot.WRIST, "Hands": Inventory.Slot.HANDS,
}
const SEPARATE: Dictionary[String, Inventory.Slot] = {
	"Weapon": Inventory.Slot.MAIN_HAND, "Shield": Inventory.Slot.OFF_HAND,
	"Ranged": Inventory.Slot.RANGED,
}
const COLORS: Dictionary[Alert, Color] = {
	Alert.DAMAGED: Color(1.0, 0.82, 0.18),
	Alert.BROKEN: Color(0.93, 0.07, 0.07),
}
const UNHURT: Color = Color(1.0, 1.0, 1.0, 0.5)
# ponytail: the client's damaged threshold is not in its Lua, a fifth of the maximum is assumed.
const DAMAGED_FRACTION: float = 0.2
const ITEM_CLASS_WEAPON: int = 2

## True while the weapon, shield or ranged figure shows, which the HUD shifts the frame for.
var wide: bool = false


func _ready() -> void:
	WowClient.session.object_updated.connect(_on_object_updated)
	refresh()


# DurabilityFrame_SetAlerts.
func refresh() -> void:
	var alerts: int = 0
	var body_hurt: bool = false
	for part: String in BODY:
		var alert: Alert = _alert(Inventory.equipped(BODY[part]))
		_part(part).self_modulate = COLORS.get(alert, UNHURT)
		body_hurt = body_hurt or alert != Alert.NONE
		alerts += int(alert != Alert.NONE)
	for part: String in BODY:
		_part(part).visible = body_hurt
	var off_hand: int = Inventory.equipped(Inventory.Slot.OFF_HAND)
	var off_info: Dictionary = WowClient.session.get_item_info(Inventory.entry(off_hand)) \
			if off_hand else {}
	var off_weapon: bool = off_info.get("class", -1) == ITEM_CLASS_WEAPON
	_part("OffWeapon" if off_weapon else "Shield").hide()
	wide = false
	for part: String in SEPARATE:
		var alert: Alert = _alert(Inventory.equipped(SEPARATE[part]))
		var texture: TextureRect = _part("OffWeapon" if part == "Shield" and off_weapon else part)
		texture.visible = alert != Alert.NONE
		texture.self_modulate = COLORS.get(alert, UNHURT)
		wide = wide or texture.visible
		alerts += int(alert != Alert.NONE)
	if visible != (alerts > 0):
		visible = alerts > 0
	layout_changed.emit()


func _alert(item: int) -> Alert:
	var session: WowSession = WowClient.session
	var most: int = session.get_field(item, "ITEM_FIELD_MAXDURABILITY") if item else 0
	if most <= 0:
		return Alert.NONE
	var left: int = session.get_field(item, "ITEM_FIELD_DURABILITY")
	if left == 0:
		return Alert.BROKEN
	return Alert.DAMAGED if left <= most * DAMAGED_FRACTION else Alert.NONE


func _part(part: String) -> TextureRect:
	return get_node("%Durability" + part)


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid() \
	or (BODY.values() + SEPARATE.values()).any(
		func(slot: Inventory.Slot) -> bool: return Inventory.equipped(slot) == guid
	):
		refresh()
