class_name CharacterFrame
extends Control

signal close_requested
signal item_hovered(slot: Inventory.Slot, button: ItemButton)
signal item_left(button: ItemButton)
signal item_used(slot: Inventory.Slot)

enum Tab { CHARACTER = 1, PET, REPUTATION, SKILLS, HONOR }

const TAB_FRAMES: Dictionary[Tab, String] = {
	Tab.CHARACTER: "PaperDollFrame",
	Tab.PET: "PetPaperDollFrame",
	Tab.REPUTATION: "ReputationFrame",
	Tab.SKILLS: "SkillFrame",
	Tab.HONOR: "HonorFrame",
}
# GetInventorySlotInfo: each paper doll button's slot and the art it shows while empty.
const SLOTS: Dictionary[String, Array] = {
	"Head": [Inventory.Slot.HEAD, "Head"],
	"Neck": [Inventory.Slot.NECK, "Neck"],
	"Shoulder": [Inventory.Slot.SHOULDER, "Shoulder"],
	"Back": [Inventory.Slot.BACK, "Chest"],
	"Chest": [Inventory.Slot.CHEST, "Chest"],
	"Shirt": [Inventory.Slot.SHIRT, "Shirt"],
	"Tabard": [Inventory.Slot.TABARD, "Tabard"],
	"Wrist": [Inventory.Slot.WRIST, "Wrists"],
	"Hands": [Inventory.Slot.HANDS, "Hands"],
	"Waist": [Inventory.Slot.WAIST, "Waist"],
	"Legs": [Inventory.Slot.LEGS, "Legs"],
	"Feet": [Inventory.Slot.FEET, "Feet"],
	"Finger0": [Inventory.Slot.FINGER_1, "Finger"],
	"Finger1": [Inventory.Slot.FINGER_2, "RFinger"],
	"Trinket0": [Inventory.Slot.TRINKET_1, "Trinket"],
	"Trinket1": [Inventory.Slot.TRINKET_2, "Trinket"],
	"MainHand": [Inventory.Slot.MAIN_HAND, "MainHand"],
	"SecondaryHand": [Inventory.Slot.OFF_HAND, "SecondaryHand"],
	"Ranged": [Inventory.Slot.RANGED, "Ranged"],
}
const EMPTY_SLOT: String = "Interface\\PaperDoll\\UI-PaperDoll-Slot-%s.blp"
const STAT_COUNT: int = 5
# MagicResFrame1 to 5 show UNIT_FIELD_RESISTANCES arcane, fire, nature, frost and shadow.
const RESISTANCE_INDEXES: Array[int] = [6, 2, 3, 4, 5]
# PaperDollFrame_OnLoad's stat labels.
const STAT_LABELS: Dictionary[String, String] = {
	"CharacterAttackFrameLabel": "MELEE_ATTACK",
	"CharacterDamageFrameLabel": "DAMAGE_COLON",
	"CharacterAttackPowerFrameLabel": "ATTACK_POWER_COLON",
	"CharacterRangedAttackFrameLabel": "RANGED_ATTACK",
	"CharacterRangedDamageFrameLabel": "DAMAGE_COLON",
	"CharacterRangedAttackPowerFrameLabel": "ATTACK_POWER_COLON",
	"CharacterArmorFrameLabel": "ARMOR_COLON",
}
const PORTRAIT: PackedScene = preload("res://game/ui/unit_portrait.tscn")
const PORTRAIT_MASK: Shader = preload("res://game/ui/portrait.gdshader")
const ROTATE_DEGREES_PER_SECOND: float = 120.0
const DRAG_DEGREES_PER_PIXEL: float = 0.6

var _tab: Tab = Tab.CHARACTER
var _slot_buttons: Dictionary[Inventory.Slot, ItemButton] = {}
var _empty_icons: Dictionary[Inventory.Slot, Texture2D] = {}
var _worn: PackedInt32Array = []
var _portrait: UnitPortrait

@onready var _model: WowModelFrame = %CharacterModelFrameModel
@onready var _rotate_left: BaseButton = %CharacterModelFrameRotateLeftButton
@onready var _rotate_right: BaseButton = %CharacterModelFrameRotateRightButton


func _ready() -> void:
	for slot_name: String in SLOTS:
		var slot: Inventory.Slot = SLOTS[slot_name][0]
		var button: ItemButton = get_node("%Character" + slot_name + "Slot")
		var empty: WowTexture = WowTexture.new()
		empty.file = EMPTY_SLOT % SLOTS[slot_name][1]
		_slot_buttons[slot] = button
		_empty_icons[slot] = empty
		button.mouse_entered.connect(func() -> void: item_hovered.emit(slot, button))
		button.mouse_exited.connect(func() -> void: item_left.emit(button))
		button.right_clicked.connect(func() -> void: item_used.emit(slot))
	for tab: Tab in TAB_FRAMES:
		(get_node("%%CharacterFrameTab%d" % tab) as BaseButton).pressed.connect(show_tab.bind(tab))
	for label_name: String in STAT_LABELS:
		var label: Label = get_node("%" + label_name)
		label.text = WowStrings.get_text(STAT_LABELS[label_name])
	for i: int in STAT_COUNT:
		var stat_label: Label = get_node("%%CharacterStatFrame%dLabel" % (i + 1))
		stat_label.text = WowStrings.get_text("SPELL_STAT%d_NAME" % i) + ":"
	%CharacterFrameCloseButton.pressed.connect(close_requested.emit)
	# CharacterNameFrame raises its frame level on load so the name draws over the tab art.
	move_child(%CharacterNameFrame, get_child_count() - 1)
	_portrait = PORTRAIT.instantiate()
	add_child(_portrait)
	var mask: ShaderMaterial = ShaderMaterial.new()
	mask.shader = PORTRAIT_MASK
	%CharacterFramePortrait.material = mask
	%CharacterFramePortrait.texture = _portrait.get_texture()
	%CharacterModelFrame.gui_input.connect(_on_model_input)
	# The pet and honor tabs wait on pets and the PvP data; the tabs after the pet tab close up.
	var gap: float = %CharacterFrameTab3.position.x - %CharacterFrameTab2.position.x
	for tab: Control in [%CharacterFrameTab3, %CharacterFrameTab4]:
		tab.position.x -= gap
	%CharacterFrameTab2.hide()
	%CharacterFrameTab5.hide()
	visibility_changed.connect(refresh)
	var session: WowSession = WowClient.session
	session.object_updated.connect(_on_object_updated)
	session.item_info_received.connect(func(_entry: int) -> void: refresh())
	show_tab(Tab.CHARACTER)


func _process(delta: float) -> void:
	var turn: float = float(_rotate_right.button_pressed) - float(_rotate_left.button_pressed)
	if turn != 0.0:
		_model.facing += turn * ROTATE_DEGREES_PER_SECOND * delta


# CharacterFrameTab_OnClick: one tab's frame shows, and its tab reads as selected.
func show_tab(tab: Tab) -> void:
	_tab = tab
	for other: Tab in TAB_FRAMES:
		var selected: bool = other == tab
		var frame: CanvasItem = get_node("%" + TAB_FRAMES[other])
		frame.visible = selected
		var prefix: String = "%%CharacterFrameTab%d" % other
		for piece: String in ["Left", "Middle", "Right"]:
			var normal: CanvasItem = get_node(prefix + piece)
			var chosen: CanvasItem = get_node(prefix + piece + "Disabled")
			normal.visible = not selected
			chosen.visible = selected
		var label: Label = get_node(prefix + "Text")
		label.theme_type_variation = \
		&"GameFontHighlightSmall" if selected else &"GameFontNormalSmall"
	refresh()


# The empty slot's tooltip, such as HEADSLOT.
static func slot_label(slot: Inventory.Slot) -> String:
	for slot_name: String in SLOTS:
		if SLOTS[slot_name][0] == slot:
			return WowStrings.get_text(slot_name.to_upper() + "SLOT")
	return ""


func current_tab() -> Tab:
	return _tab


func refresh() -> void:
	if not is_visible_in_tree() or _tab != Tab.CHARACTER:
		return
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	var race: int = session.get_field(guid, "UNIT_FIELD_BYTES_0") & 0xFF
	var class_id: int = (session.get_field(guid, "UNIT_FIELD_BYTES_0") >> 8) & 0xFF
	%CharacterNameText.text = session.get_object_name(guid)
	%CharacterLevelText.text = WowStrings.get_text("PLAYER_LEVEL") % [
		session.get_field(guid, "UNIT_FIELD_LEVEL"), CharacterOptions.race_name(race),
		CharacterOptions.class_label(class_id),
	]
	for slot: Inventory.Slot in _slot_buttons:
		var item_entry: int = Inventory.entry(Inventory.equipped(slot))
		var icon: Texture2D = Inventory.icon(item_entry) if item_entry else null
		_slot_buttons[slot].set_item(icon if icon else _empty_icons[slot])
	_set_stats(session, guid)
	var worn: PackedInt32Array = CharacterModels.visible_items(session, guid)
	if worn != _worn or _model.get_node("%Scene").get_child_count() == 0:
		_worn = worn
		_portrait.show_unit(guid)
		var display: int = session.get_field(guid, "UNIT_FIELD_DISPLAYID")
		var look: Dictionary = CharacterModels.player_look(session, guid)
		_model.frame_character(WowAssets.creatures.instantiate(display, look))


# PaperDollFrame_SetStats and friends: buffed values show green, debuffed ones red.
func _set_stats(session: WowSession, guid: int) -> void:
	for i: int in STAT_COUNT:
		_set_value(
			get_node("%%CharacterStatFrame%dStatText" % (i + 1)),
			session.get_field(guid, "UNIT_FIELD_STAT%d" % i),
			session.get_field(guid, "PLAYER_FIELD_POSSTAT%d" % i),
			_signed(session.get_field(guid, "PLAYER_FIELD_NEGSTAT%d" % i)),
		)
	var resistances: int = session.field_index("UNIT_FIELD_RESISTANCES")
	var armor_buff: int = session.field_index("PLAYER_FIELD_RESISTANCEBUFFMODSPOSITIVE")
	var armor_debuff: int = session.field_index("PLAYER_FIELD_RESISTANCEBUFFMODSNEGATIVE")
	_set_value(
		%CharacterArmorFrameStatText, session.get_field(guid, resistances),
		session.get_field(guid, armor_buff), _signed(session.get_field(guid, armor_debuff)),
	)
	for i: int in RESISTANCE_INDEXES.size():
		var text: Label = get_node("%%MagicResText%d" % (i + 1))
		text.text = str(session.get_field(guid, resistances + RESISTANCE_INDEXES[i]))
	var power_mods: int = session.get_field(guid, "UNIT_FIELD_ATTACK_POWER_MODS")
	var power_buff: int = _signed_short(power_mods & 0xFFFF)
	var power_debuff: int = _signed_short(power_mods >> 16)
	_set_value(
		%CharacterAttackPowerFrameStatText,
		session.get_field(guid, "UNIT_FIELD_ATTACK_POWER") + power_buff + power_debuff,
		power_buff, power_debuff,
	)
	%CharacterDamageFrameStatText.text = "%d - %d" % [
		session.get_field_float(guid, "UNIT_FIELD_MINDAMAGE"),
		session.get_field_float(guid, "UNIT_FIELD_MAXDAMAGE"),
	]
	# ponytail: attack rating is the level's skill cap; read the real skill with the skills tab.
	%CharacterAttackFrameStatText.text = str(session.get_field(guid, "UNIT_FIELD_LEVEL") * 5)
	var has_ranged: bool = Inventory.equipped(Inventory.Slot.RANGED) != 0
	var not_applicable: String = WowStrings.get_text("NOT_APPLICABLE")
	var ranged_mods: int = session.get_field(guid, "UNIT_FIELD_RANGED_ATTACK_POWER_MODS")
	%CharacterRangedAttackFrameStatText.text = \
	str(session.get_field(guid, "UNIT_FIELD_LEVEL") * 5) if has_ranged else not_applicable
	%CharacterRangedAttackPowerFrameStatText.text = str(
		session.get_field(guid, "UNIT_FIELD_RANGED_ATTACK_POWER")
		+ _signed_short(ranged_mods & 0xFFFF) + _signed_short(ranged_mods >> 16)
	) if has_ranged else not_applicable
	%CharacterRangedDamageFrameStatText.text = "%d - %d" % [
		session.get_field_float(guid, "UNIT_FIELD_MINRANGEDDAMAGE"),
		session.get_field_float(guid, "UNIT_FIELD_MAXRANGEDDAMAGE"),
	] if has_ranged else not_applicable


# PaperDollFormatStat: effective is base plus both buffs; any debuff turns it red, a buff green.
func _set_value(label: Label, effective: int, buff: int, debuff: int) -> void:
	label.text = str(maxi(effective, 0))
	label.theme_type_variation = &"GameFontRedSmall" if debuff < 0 \
	else &"GameFontGreenSmall" if buff > 0 else &"GameFontHighlightSmall"


func _signed(value: int) -> int:
	return value - 0x100000000 if value >= 0x80000000 else value


func _signed_short(value: int) -> int:
	return value - 0x10000 if value >= 0x8000 else value


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid():
		refresh()


func _on_model_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_model.facing += motion.relative.x * DRAG_DEGREES_PER_PIXEL
