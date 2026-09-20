class_name UIOptionsFrame
extends Control

signal close_requested

# Check button numbers and the global string that names each one, from UIOptionsFrame.lua.
const CHECK_TEXTS: Dictionary[int, String] = {
	1: "INVERT_MOUSE", 2: "STATUS_BAR_TEXT", 3: "ASSIST_ATTACK", 5: "PROFANITY_FILTER",
	6: "CLICK_TO_MOVE", 7: "SIMPLE_CHAT_TEXT", 8: "CHAT_LOCKED_TEXT", 9: "SHOW_PET_MELEE_DAMAGE",
	11: "LOG_PERIODIC_EFFECTS", 12: "USE_UBERTOOLTIPS", 13: "GUILDMEMBER_ALERT",
	14: "BLOCK_TRADES", 15: "SMART_PIVOT", 16: "CLEAR_AFK", 18: "REMOVE_CHAT_DELAY_TEXT",
	19: "SHOW_DAMAGE_TEXT", 20: "SHOW_HELM", 21: "SHOW_PLAYER_NAMES", 22: "SHOW_GUILD_NAMES",
	23: "SHOW_PLAYER_TITLES", 24: "FOLLOW_TERRAIN", 26: "HEAD_BOB", 27: "WATER_COLLISION",
	28: "SHOW_TUTORIALS", 29: "SHOW_NEWBIE_TIPS_TEXT", 30: "SHOW_NPC_NAMES", 31: "SHOW_CLOAK",
	32: "LOCK_ACTIONBAR_TEXT", 33: "SHOW_MULTIBAR1_TEXT", 34: "SHOW_MULTIBAR2_TEXT",
	35: "SHOW_MULTIBAR3_TEXT", 36: "SHOW_MULTIBAR4_TEXT", 37: "CHAT_BUBBLES_TEXT",
	38: "PARTY_CHAT_BUBBLES_TEXT", 39: "SHOW_BUFF_DURATION_TEXT",
	40: "ALWAYS_SHOW_MULTIBARS_TEXT", 41: "SHOW_PARTY_PETS_TEXT", 42: "SHOW_QUEST_FADING_TEXT",
	43: "SHOW_PARTY_BACKGROUND_TEXT", 44: "SHOW_TIPOFTHEDAY_TEXT", 45: "GAMEFIELD_DESELECT_TEXT",
	46: "SHOW_LOOT_SPAM", 47: "HIDE_PARTY_INTERFACE_TEXT", 48: "SHOW_DISPELLABLE_DEBUFFS_TEXT",
	49: "SHOW_CASTABLE_BUFFS_TEXT", 50: "SHOW_TARGET_OF_TARGET_TEXT",
	51: "AUTO_JOIN_GUILD_CHANNEL", 52: "SHOW_COMBAT_TEXT_TEXT",
	53: "COMBAT_TEXT_SHOW_LOW_HEALTH_MANA_TEXT", 54: "COMBAT_TEXT_SHOW_AURAS_TEXT",
	55: "COMBAT_TEXT_SHOW_AURA_FADE_TEXT", 56: "COMBAT_TEXT_SHOW_COMBAT_STATE_TEXT",
	57: "COMBAT_TEXT_SHOW_DODGE_PARRY_MISS_TEXT", 58: "COMBAT_TEXT_SHOW_RESISTANCES_TEXT",
	59: "COMBAT_TEXT_SHOW_MANA_TEXT", 60: "COMBAT_TEXT_SHOW_REPUTATION_TEXT",
	61: "AUTO_SELF_CAST_TEXT", 62: "HIDE_OUTDOOR_WORLD_STATE_TEXT",
	63: "COMBAT_TEXT_SHOW_REACTIVES_TEXT", 64: "COMBAT_TEXT_SHOW_FRIENDLY_NAMES_TEXT",
	65: "COMBAT_TEXT_SHOW_COMBO_POINTS_TEXT", 66: "AUTO_QUEST_WATCH_TEXT", 67: "SHOW_OWN_NAME",
	68: "DISABLE_SPAM_FILTER", 69: "COMBAT_TEXT_SHOW_HONOR_GAINED_TEXT",
}
# The options this client answers; the rest stay on show but greyed out.
const CHECK_OPTIONS: Dictionary[int, StringName] = {
	1: &"invert_mouse", 2: &"status_bar_text", 21: &"show_player_names",
	30: &"show_npc_names", 33: &"multi_bar_1", 34: &"multi_bar_2",
	35: &"multi_bar_3", 36: &"multi_bar_4", 37: &"chat_bubbles", 38: &"party_chat_bubbles",
	39: &"show_buff_durations", 66: &"auto_quest_watch", 
}

# What the options stood at when the window opened, so Cancel can put them back.
var _opened: Dictionary[StringName, bool] = {}
var _accepted: bool = false


func _ready() -> void:
	for number: int in CHECK_TEXTS:
		var check: WowButton = get_node_or_null("%%UIOptionsFrameCheckButton%d" % number)
		if check == null:
			continue
		var label: Label = check.get_node_or_null("UIOptionsFrameCheckButton%dText" % number)
		if label:
			label.text = WowStrings.get_text(CHECK_TEXTS[number])
		if CHECK_OPTIONS.has(number):
			check.pressed.connect(_on_check_pressed.bind(number))
		else:
			check.disabled = true
	%UIOptionsFrameOkay.pressed.connect(_on_okay_pressed)
	%UIOptionsFrameCancel.pressed.connect(close_requested.emit)
	%UIOptionsFrameDefaults.pressed.connect(_on_defaults_pressed)
	visibility_changed.connect(_on_visibility_changed)


func _refresh() -> void:
	var settings: InterfaceSettings = WowAssets.interface
	for number: int in CHECK_OPTIONS:
		var check: WowButton = get_node_or_null("%%UIOptionsFrameCheckButton%d" % number)
		if check:
			check.checked = settings.is_on(CHECK_OPTIONS[number])


# Options apply as they are ticked, so closing any way but Okay puts the old ones back.
func _on_visibility_changed() -> void:
	var settings: InterfaceSettings = WowAssets.interface
	if not is_visible_in_tree():
		if not _accepted:
			for option: StringName in _opened:
				settings.set_on(option, _opened[option])
		return
	_accepted = false
	_opened.clear()
	for option: StringName in InterfaceSettings.OPTIONS:
		_opened[option] = settings.is_on(option)
	_refresh()


func _on_check_pressed(number: int) -> void:
	var option: StringName = CHECK_OPTIONS[number]
	WowAssets.interface.set_on(option, not WowAssets.interface.is_on(option))
	_refresh()


func _on_okay_pressed() -> void:
	_accepted = true
	WowAssets.interface.save()
	close_requested.emit()


func _on_defaults_pressed() -> void:
	WowAssets.interface.restore_defaults()
	_refresh()
