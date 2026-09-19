class_name MainMenuBar
extends Control

signal action_used(slot: int)
signal panel_toggled(panel: GamePanel)
signal bottom_bars_toggled(shown: bool)
signal bag_toggled(bag: int)

enum GamePanel {
	CHARACTER, SPELLBOOK, TALENTS, QUEST_LOG, SOCIAL, WORLD_MAP, GAME_MENU, HELP, BAGS,
}
enum RestState { RESTED = 1, NORMAL = 2 }

const BUTTONS_PER_PAGE: int = 12
const PAGE_COUNT: int = 6
# MultiBarBottomLeft and MultiBarBottomRight hold action pages 6 and 5.
const BOTTOM_LEFT_FIRST_SLOT: int = 60
const BOTTOM_RIGHT_FIRST_SLOT: int = 48
# Forms (UNIT_FIELD_BYTES_1 byte 2) whose first page is a bonus bar, as in GetBonusBarOffset.
const BONUS_PAGE_BY_FORM: Dictionary[int, int] = {
	1: 7, 5: 9, 8: 9, 17: 7, 18: 8, 19: 9, 30: 7,
}
const XP_COLORS: Dictionary[RestState, Color] = {
	RestState.RESTED: Color(0.0, 0.39, 0.88),
	RestState.NORMAL: Color(0.58, 0.0, 0.55),
}
const RESTED_FILL: Color = Color(0.0, 0.39, 0.88, 0.25)
const KEY_SYMBOLS: Dictionary[String, String] = {"Minus": "-", "Equal": "="}
# MicroButtonTooltipText: the button's name, its key binding and the newbie tip, per panel.
const PANEL_TIPS: Dictionary[GamePanel, Array] = {
	GamePanel.CHARACTER: ["CHARACTER_BUTTON", "NEWBIE_TOOLTIP_CHARACTER", "toggle_character"],
	GamePanel.SPELLBOOK: [
		"SPELLBOOK_ABILITIES_BUTTON", "NEWBIE_TOOLTIP_SPELLBOOK", "toggle_spellbook",
	],
	GamePanel.TALENTS: ["TALENTS_BUTTON", "NEWBIE_TOOLTIP_TALENTS", "toggle_talents"],
	GamePanel.QUEST_LOG: ["QUESTLOG_BUTTON", "NEWBIE_TOOLTIP_QUESTLOG", "toggle_quest_log"],
	GamePanel.SOCIAL: ["SOCIAL_BUTTON", "NEWBIE_TOOLTIP_SOCIAL", "toggle_social"],
	GamePanel.WORLD_MAP: ["WORLDMAP_BUTTON", "NEWBIE_TOOLTIP_WORLDMAP", "toggle_world_map"],
	GamePanel.GAME_MENU: ["MAINMENU_BUTTON", "NEWBIE_TOOLTIP_MAINMENU", ""],
	GamePanel.HELP: ["HELP_BUTTON", "NEWBIE_TOOLTIP_HELP", ""],
	GamePanel.BAGS: ["BACKPACK_TOOLTIP", "", "toggle_bags"],
}

var page: int = 1:
	set(value):
		page = wrapi(value, 1, PAGE_COUNT + 1)
		_assign_slots()

var _buttons: Array[ActionButton] = []
var _bottom_left: Array[ActionButton] = []
var _bottom_right: Array[ActionButton] = []
var _shown_page: int = 0
var _empty_bag_icons: Array[Texture2D] = []

@onready var _page_number: Label = %MainMenuBarPageNumber
@onready var _bottom_left_bar: Control = %MultiBarBottomLeft
@onready var _bottom_right_bar: Control = %MultiBarBottomRight
@onready var _xp_bar: TextureProgressBar = %MainMenuExpBar
@onready var _xp_text: Label = %MainMenuBarExpText
@onready var _rested: ColorRect = %ExhaustionLevelFillBar
@onready var _micro_buttons: Dictionary[BaseButton, GamePanel] = {
	%CharacterMicroButton: GamePanel.CHARACTER,
	%SpellbookMicroButton: GamePanel.SPELLBOOK,
	%TalentMicroButton: GamePanel.TALENTS,
	%QuestLogMicroButton: GamePanel.QUEST_LOG,
	%SocialsMicroButton: GamePanel.SOCIAL,
	%WorldMapMicroButton: GamePanel.WORLD_MAP,
	%MainMenuMicroButton: GamePanel.GAME_MENU,
	%HelpMicroButton: GamePanel.HELP,
	%MainMenuBarBackpackButton: GamePanel.BAGS,
}


func _ready() -> void:
	for i: int in BUTTONS_PER_PAGE:
		var button: ActionButton = get_node("%%ActionButton%d" % (i + 1))
		button.hotkey = _hotkey_text("action_button_%d" % (i + 1))
		button.used.connect(action_used.emit)
		_buttons.append(button)
	for button: BaseButton in _micro_buttons:
		button.pressed.connect(panel_toggled.emit.bind(_micro_buttons[button]))
		button.mouse_entered.connect(_on_micro_button_hovered.bind(button))
		button.mouse_exited.connect(_on_micro_button_left.bind(button))
	for bag: int in range(1, Inventory.BAG_COUNT + 1):
		var slot: WowButton = _bag_button(bag)
		slot.pressed.connect(bag_toggled.emit.bind(bag))
		_empty_bag_icons.append(_bag_icon(bag).texture)
	%ActionBarUpButton.pressed.connect(func() -> void: page += 1)
	%ActionBarDownButton.pressed.connect(func() -> void: page -= 1)
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_xp_bar.mouse_entered.connect(_xp_text.show)
	_xp_bar.mouse_exited.connect(_xp_text.hide)
	_xp_text.hide()
	_bottom_left = MultiActionBar.bind(_bottom_left_bar, BOTTOM_LEFT_FIRST_SLOT, action_used.emit)
	_bottom_right = MultiActionBar.bind(_bottom_right_bar, BOTTOM_RIGHT_FIRST_SLOT, action_used.emit)
	WowClient.session.action_buttons_changed.connect(_update_bottom_bars)
	WowClient.session.object_updated.connect(_on_object_updated)
	# The player's own create block brings the stance, and it can land after the bar is built.
	WowClient.session.object_created.connect(func(guid: int, _type: int) -> void: _on_object_updated(guid))
	_assign_slots()
	_update_xp()
	_update_bottom_bars()
	_update_bags()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	for i: int in BUTTONS_PER_PAGE:
		if event.is_action_pressed("action_button_%d" % (i + 1), false, true):
			get_viewport().set_input_as_handled()
			action_used.emit(_buttons[i].slot)
			return
	for i: int in PAGE_COUNT:
		if event.is_action_pressed("action_page_%d" % (i + 1), false, true):
			get_viewport().set_input_as_handled()
			page = i + 1
			return


func _assign_slots() -> void:
	if _buttons.is_empty():
		return
	var shown: int = page
	if page == 1:
		shown = BONUS_PAGE_BY_FORM.get(_player_form(), 1)
	if shown == _shown_page:
		return
	_shown_page = shown
	for i: int in BUTTONS_PER_PAGE:
		_buttons[i].slot = (shown - 1) * BUTTONS_PER_PAGE + i
	_page_number.text = str(page)


func _update_bottom_bars() -> void:
	MultiActionBar.update_visibility(_bottom_left_bar, _bottom_left)
	MultiActionBar.update_visibility(_bottom_right_bar, _bottom_right)
	bottom_bars_toggled.emit(_bottom_left_bar.visible or _bottom_right_bar.visible)


func _player_form() -> int:
	var session: WowSession = WowClient.session
	return (session.get_field(session.get_player_guid(), "UNIT_FIELD_BYTES_1") >> 16) & 0xFF


func _update_xp() -> void:
	var session: WowSession = WowClient.session
	var guid: int = session.get_player_guid()
	var xp: int = session.get_field(guid, "PLAYER_XP")
	var next: int = maxi(session.get_field(guid, "PLAYER_NEXT_LEVEL_XP"), 1)
	var rest: int = session.get_field(guid, "PLAYER_REST_STATE_EXPERIENCE")
	var state: int = (session.get_field(guid, "PLAYER_BYTES_2") >> 24) & 0xFF
	_xp_bar.max_value = next
	_xp_bar.value = xp
	_xp_bar.tint_progress = XP_COLORS.get(state as RestState, XP_COLORS[RestState.NORMAL])
	_rested.color = RESTED_FILL
	_rested.visible = rest > 0
	_rested.size.x = _xp_bar.size.x * minf(float(xp + rest) / next, 1.0)
	_xp_text.text = "XP: %d / %d" % [xp, next]


# Vanilla's short form: the key, prefixed with s-, c- or a- for its modifiers.
func _hotkey_text(action: String) -> String:
	for event: InputEvent in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key == null:
			continue
		var code: Key = key.keycode if key.keycode != KEY_NONE \
		else DisplayServer.keyboard_get_label_from_physical(key.physical_keycode)
		var text: String = OS.get_keycode_string(code)
		text = KEY_SYMBOLS.get(text, text)
		if key.alt_pressed:
			text = "a-" + text
		if key.ctrl_pressed:
			text = "c-" + text
		if key.shift_pressed:
			text = "s-" + text
		return text
	return ""


# The backpack button and the bag slots stay checked while their bag is open.
func set_bag_open(bag: int, is_open: bool) -> void:
	_bag_button(bag).checked = is_open


func _bag_button(bag: int) -> WowButton:
	if bag == Inventory.BACKPACK:
		return %MainMenuBarBackpackButton
	return get_node("%%CharacterBag%dSlot" % (bag - 1))


func _bag_icon(bag: int) -> TextureRect:
	return get_node("%%CharacterBag%dSlotIconTexture" % (bag - 1))


func _update_bags() -> void:
	for bag: int in range(1, Inventory.BAG_COUNT + 1):
		var slot: Inventory.Slot = (Inventory.Slot.BAG_1 + bag - 1) as Inventory.Slot
		var bag_entry: int = Inventory.entry(Inventory.equipped(slot))
		var icon: Texture2D = Inventory.icon(bag_entry) if bag_entry else null
		_bag_icon(bag).texture = icon if icon else _empty_bag_icons[bag - 1]


func _on_micro_button_hovered(button: BaseButton) -> void:
	if GameTooltip.current == null:
		return
	var tip: Array = PANEL_TIPS[_micro_buttons[button]]
	var hotkey: String = _hotkey_text(tip[2]) if not String(tip[2]).is_empty() else ""
	var newbie: String = WowStrings.get_text(tip[1]) if not String(tip[1]).is_empty() else ""
	var binding: String = "(%s)" % hotkey if not hotkey.is_empty() else ""
	GameTooltip.current.set_text(button, WowStrings.get_text(tip[0]), newbie, binding)


func _on_micro_button_left(button: BaseButton) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(button)


func _on_object_updated(guid: int) -> void:
	if guid == WowClient.session.get_player_guid():
		_update_xp()
		_assign_slots()
		_update_bags()
