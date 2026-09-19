class_name Hud
extends Control

signal action_used(slot: int)
signal spell_used(spell_id: int)
signal unit_selected(guid: int)

# WoW lays the interface out on a screen 768 units tall and scales it to the window.
const UI_HEIGHT: float = 768.0
const ERROR_COLOR: Color = Color(1.0, 0.1, 0.1)
const NOTICE_COLOR: Color = Color(1.0, 0.82, 0.0)
# TYPEID_ITEM and TYPEID_CONTAINER.
const ITEM_TYPES: Array[int] = [1, 2]
# UIParent_ManageFramePositions lifts the casting bar clear of the bottom action bars.
const CASTING_BAR_LIFT: float = 40.0
const SPELL_FAILURES: String = "res://data/classic/spell_failures.json"
const SWING_ERRORS: Dictionary[WowSession.AttackError, String] = {
	WowSession.ATTACK_ERROR_NOT_IN_RANGE: "ERR_BADATTACKPOS",
	WowSession.ATTACK_ERROR_BAD_FACING: "ERR_BADATTACKFACING",
	WowSession.ATTACK_ERROR_NOT_STANDING: "ERR_CANTATTACK_NOTSTANDING",
	WowSession.ATTACK_ERROR_DEAD_TARGET: "ERR_INVALID_ATTACK_TARGET",
	WowSession.ATTACK_ERROR_CANT_ATTACK: "ERR_INVALID_ATTACK_TARGET",
}
# SPELL_FAILED_NO_POWER names the power the player lacks.
const OUT_OF_POWER: Array[String] = [
	"ERR_OUT_OF_MANA", "ERR_OUT_OF_RAGE", "ERR_OUT_OF_FOCUS", "ERR_OUT_OF_ENERGY",
]

var _area: int = 0
var _spell_failures: Dictionary = {}
var _casting_bar_top: float = 0.0

@onready var _ui_parent: Control = %UIParent
@onready var _main_menu_bar: MainMenuBar = %MainMenuBar
@onready var _player_frame: PlayerFrame = %PlayerFrame
@onready var _target_frame: TargetFrame = %TargetFrame
@onready var _errors: WowMessageFrame = %UIErrorsFrame
@onready var _casting_bar: CastingBar = %CastingBarFrame
@onready var _side_bars: SideActionBars = %MultiBarRight
@onready var _minimap: MinimapCluster = %MinimapCluster
@onready var _chat: ChatFrame = %ChatFrame1
@onready var _panels: PanelManager = %UIPanels
@onready var _character: CharacterFrame = _panels.get_node("%CharacterFrame")
@onready var _game_menu: Control = _panels.get_node("%GameMenuFrame")
@onready var _spell_book: SpellBook = _panels.get_node("%SpellBookFrame")
@onready var _talents: TalentFrame = _panels.get_node("%TalentFrame")
@onready var _quest_log: QuestLogFrame = _panels.get_node("%QuestLogFrame")
@onready var _popup: StaticPopup = _panels.get_node("%StaticPopup1")
@onready var _gossip: GossipFrame = _panels.get_node("%GossipFrame")
@onready var _quest_watch: QuestWatchFrame = %QuestWatchFrame
@onready var _merchant: MerchantFrame = _panels.get_node("%MerchantFrame")
@onready var _trainer: ClassTrainerFrame = _panels.get_node("%ClassTrainerFrame")
@onready var _taxi: TaxiFrame = _panels.get_node("%TaxiFrame")
@onready var _world_map: WorldMapFrame = _panels.get_node("%WorldMapFrame")
@onready var _quest_frame: QuestFrame = _panels.get_node("%QuestFrame")


func _ready() -> void:
	WowFonts.apply()
	resized.connect(_fit_ui_parent)
	_fit_ui_parent()
	_main_menu_bar.action_used.connect(action_used.emit)
	_main_menu_bar.panel_toggled.connect(_on_panel_toggled)
	_main_menu_bar.bag_toggled.connect(_panels.toggle_bag)
	_panels.bag_opened.connect(_main_menu_bar.set_bag_open)
	for container: ContainerFrame in _panels.find_children("*", "ContainerFrame", false, false):
		container.item_used.connect(use_container_item)
		container.item_hovered.connect(_on_container_item_hovered)
		container.item_left.connect(_hide_tooltip)
	_spell_book.spell_used.connect(spell_used.emit)
	_quest_log.abandon_requested.connect(_on_abandon_requested)
	_character.unlearn_requested.connect(_on_unlearn_requested)
	_gossip.open_requested.connect(_panels.show_panel.bind(_gossip))
	_quest_frame.open_requested.connect(_panels.show_panel.bind(_quest_frame))
	_quest_frame.error_raised.connect(show_error)
	_quest_log.watch_toggled.connect(_quest_watch.toggle)
	_quest_watch.watches_changed.connect(_quest_log.set_watched)
	_quest_watch.error_raised.connect(show_error)
	_merchant.open_requested.connect(_panels.show_panel.bind(_merchant))
	_merchant.backpack_requested.connect(_panels.set_backpack_open)
	_merchant.error_raised.connect(show_error)
	_trainer.open_requested.connect(_panels.show_panel.bind(_trainer))
	_taxi.open_requested.connect(_panels.show_panel.bind(_taxi))
	_taxi.error_raised.connect(show_error)
	WowClient.session.taxi_path_discovered.connect(
		func() -> void: show_notice(WowStrings.get_text("ERR_NEWTAXIPATH"))
	)
	TaxiNodes.load_known()
	WowClient.session.quest_kill_added.connect(_on_quest_kill_added)
	WowClient.session.quest_completed.connect(_on_quest_completed)
	_character.item_hovered.connect(_on_equipped_item_hovered)
	_character.item_left.connect(_hide_tooltip)
	_side_bars.action_used.connect(action_used.emit)
	_casting_bar_top = _casting_bar.offset_top
	_main_menu_bar.bottom_bars_toggled.connect(_on_bottom_bars_toggled)
	_on_bottom_bars_toggled(_main_menu_bar.get_node("%MultiBarBottomLeft").visible)
	_player_frame.unit_selected.connect(unit_selected.emit)
	WowClient.session.spell_cast_failed.connect(_on_spell_cast_failed)
	WowClient.session.attack_swing_error.connect(_on_attack_swing_error)
	WowClient.session.object_updated.connect(_on_object_updated)
	WowClient.session.item_info_received.connect(func(_entry: int) -> void: _panels.refresh_bags())
	_spell_failures = JSON.parse_string(FileAccess.get_file_as_string(SPELL_FAILURES))


func _unhandled_input(event: InputEvent) -> void:
	var typing: bool = get_viewport().gui_get_focus_owner() is LineEdit
	if not event.is_pressed() or event.is_echo() or typing:
		return
	if event.is_action_pressed("ui_cancel"):
		_escape()
	elif _exact(event, "toggle_character"):
		_toggle_character(CharacterFrame.Tab.CHARACTER)
	elif _exact(event, "toggle_skills"):
		_toggle_character(CharacterFrame.Tab.SKILLS)
	elif _exact(event, "toggle_reputation"):
		_toggle_character(CharacterFrame.Tab.REPUTATION)
	elif _exact(event, "toggle_spellbook"):
		_panels.toggle_panel(_spell_book)
	elif _exact(event, "toggle_talents"):
		_panels.toggle_panel(_talents)
	elif _exact(event, "toggle_quest_log"):
		_panels.toggle_panel(_quest_log)
	elif _exact(event, "toggle_world_map"):
		_panels.toggle_panel(_world_map)
	elif _exact(event, "toggle_bags"):
		_panels.open_all_bags()
	elif _exact(event, "toggle_backpack"):
		_panels.toggle_backpack()
	else:
		# TOGGLEBAG1 opens the leftmost bag, the fourth bag slot.
		for i: int in Inventory.BAG_COUNT:
			if _exact(event, "toggle_bag_%d" % (i + 1)):
				_panels.toggle_bag(Inventory.BAG_COUNT - i)
				get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()


func show_player(guid: int) -> void:
	_player_frame.show_unit(guid)


func show_target(guid: int) -> void:
	_target_frame.show_unit(guid)


func target() -> int:
	return _target_frame.guid if _target_frame.visible else 0


func add_chat_line(text: String, color: Color = Color.WHITE) -> void:
	_chat.add_message(text, color)


func show_location(map_dir: String, wow_position: Vector3, facing: float) -> void:
	_minimap.show_location(map_dir, wow_position, facing)
	_world_map.set_player(map_dir, wow_position, facing, _area)


func show_area(area_id: int, player_race: int) -> void:
	_area = area_id
	_minimap.show_area(area_id, player_race)


func show_error(text: String) -> void:
	_errors.add_message(text, ERROR_COLOR)


func show_notice(text: String) -> void:
	_errors.add_message(text, NOTICE_COLOR)


func _exact(event: InputEvent, action: String) -> bool:
	return event.is_action_pressed(action, false, true)


# ToggleGameMenu: each Escape does the first of these that applies.
func _escape() -> void:
	if _popup.cancel():
		pass
	elif _game_menu.visible:
		_panels.hide_panel(_game_menu)
	elif _casting_bar.spell_id != 0:
		WowClient.session.cancel_cast(_casting_bar.spell_id)
	elif _panels.close_all_windows():
		pass
	elif target() != 0:
		unit_selected.emit(0)
	else:
		_panels.show_panel(_game_menu)


func _on_abandon_requested(slot: int, title: String) -> void:
	_popup.ask(WowStrings.get_text("ABANDON_QUEST_CONFIRM") % title, _quest_log.abandon.bind(slot))


func _on_quest_kill_added(_quest: int, entry: int, count: int, required: int) -> void:
	var creature: String = WowClient.session.get_creature_template(entry).get("name", "")
	show_notice(WowStrings.get_text("ERR_QUEST_ADD_KILL_SII") % [creature, count, required])


func _on_quest_completed(quest: int, _xp: int, _money: int) -> void:
	var title: String = WowClient.session.get_quest_info(quest).get("title", "")
	show_notice(WowStrings.get_text("ERR_QUEST_COMPLETE_S") % title)


func _on_unlearn_requested(skill_id: int, skill_name: String) -> void:
	var text: String = WowStrings.get_text("UNLEARN_SKILL") % skill_name
	_popup.ask(text, _character.unlearn_skill.bind(skill_id), "UNLEARN", "CANCEL")


# ToggleCharacter: the key for the tab already showing closes the frame.
func _toggle_character(tab: CharacterFrame.Tab) -> void:
	if _character.visible and _character.current_tab() == tab:
		_panels.hide_panel(_character)
		return
	_character.show_tab(tab)
	_panels.show_panel(_character)


func _on_panel_toggled(panel: MainMenuBar.GamePanel) -> void:
	match panel:
		MainMenuBar.GamePanel.CHARACTER:
			_toggle_character(CharacterFrame.Tab.CHARACTER)
		MainMenuBar.GamePanel.SPELLBOOK:
			_panels.toggle_panel(_spell_book)
		MainMenuBar.GamePanel.TALENTS:
			_panels.toggle_panel(_talents)
		MainMenuBar.GamePanel.QUEST_LOG:
			_panels.toggle_panel(_quest_log)
		MainMenuBar.GamePanel.WORLD_MAP:
			_panels.toggle_panel(_world_map)
		MainMenuBar.GamePanel.BAGS:
			_panels.toggle_backpack()
		MainMenuBar.GamePanel.GAME_MENU:
			if _game_menu.visible:
				_panels.hide_panel(_game_menu)
			else:
				_panels.close_all_windows()
				_panels.show_panel(_game_menu)


# UseContainerItem: gear equips, everything else is used.
func use_container_item(bag: int, slot: int) -> void:
	var item: int = Inventory.container_item(bag, slot)
	var item_entry: int = Inventory.entry(item)
	if item_entry == 0:
		return
	if _merchant.vendor() != 0:
		_merchant.sell(item)
		return
	var address: Vector2i = Inventory.wire_address(bag, slot)
	var session: WowSession = WowClient.session
	if session.get_item_info(item_entry).get("inventory_type", 0) != 0:
		session.send_packet("CMSG_AUTOEQUIP_ITEM", PackedByteArray([address.x, address.y]))
	else:
		# Bag and slot, spell slot 0, and a target mask of 0, which is the player.
		session.send_packet("CMSG_USE_ITEM", PackedByteArray([address.x, address.y, 0, 0, 0]))


func _on_container_item_hovered(bag: int, slot: int, button: ItemButton) -> void:
	var item: int = Inventory.container_item(bag, slot)
	if item and GameTooltip.current:
		var anchor: GameTooltip.TooltipAnchor = GameTooltip.TooltipAnchor.LEFT
		GameTooltip.current.set_item(button, Inventory.entry(item), item, anchor)


func _on_equipped_item_hovered(slot: Inventory.Slot, button: ItemButton) -> void:
	if GameTooltip.current == null:
		return
	var item: int = Inventory.equipped(slot)
	if item:
		GameTooltip.current.set_item(button, Inventory.entry(item), item)
	else:
		GameTooltip.current.set_text(button, CharacterFrame.slot_label(slot))


func _hide_tooltip(button: ItemButton) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(button)


# Bags follow the player's slots, their containers and the items in them.
func _on_object_updated(guid: int) -> void:
	var session: WowSession = WowClient.session
	if guid == session.get_player_guid() or session.get_object_type(guid) in ITEM_TYPES:
		_panels.refresh_bags()


func _on_bottom_bars_toggled(shown: bool) -> void:
	var height: float = _casting_bar.offset_bottom - _casting_bar.offset_top
	_casting_bar.offset_top = _casting_bar_top - (CASTING_BAR_LIFT if shown else 0.0)
	_casting_bar.offset_bottom = _casting_bar.offset_top + height


func _fit_ui_parent() -> void:
	var ui_scale: float = size.y / UI_HEIGHT
	_ui_parent.scale = Vector2(ui_scale, ui_scale)
	_ui_parent.size = size / ui_scale


# Interrupts arrive with reason -1 and are shown by the casting bar instead.
func _on_spell_cast_failed(caster: int, _spell_id: int, reason: int) -> void:
	var session: WowSession = WowClient.session
	if caster != session.get_player_guid() or reason < 0:
		return
	var key: String = _spell_failures.get(str(reason), "")
	if key == "SPELL_FAILED_NO_POWER":
		var power: int = (session.get_field(caster, "UNIT_FIELD_BYTES_0") >> 24) & 0xFF
		key = OUT_OF_POWER[power] if power < OUT_OF_POWER.size() else key
	if not key.is_empty():
		show_error(WowStrings.get_text(key))


func _on_attack_swing_error(error: WowSession.AttackError) -> void:
	show_error(WowStrings.get_text(SWING_ERRORS[error]))


