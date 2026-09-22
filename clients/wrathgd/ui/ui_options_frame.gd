class_name UIOptionsFrame
extends Control

signal close_requested

# The 3.3.5 check button that carries each option this client answers.
const CHECK_OPTIONS: Dictionary[String, StringName] = {
	"InterfaceOptionsMousePanelInvertMouse": &"invert_mouse",
	"InterfaceOptionsDisplayPanelShowHelm": &"show_helm",
	"InterfaceOptionsDisplayPanelShowCloak": &"show_cloak",
	"InterfaceOptionsNamesPanelFriendlyPlayerNames": &"show_player_names",
	"InterfaceOptionsNamesPanelNPCNames": &"show_npc_names",
	"InterfaceOptionsNamesPanelMyName": &"show_own_name",
	"InterfaceOptionsHelpPanelShowTutorials": &"show_tutorials",
	"InterfaceOptionsHelpPanelLoadingScreenTips": &"show_game_tips",
	"InterfaceOptionsActionBarsPanelBottomLeft": &"multi_bar_1",
	"InterfaceOptionsActionBarsPanelBottomRight": &"multi_bar_2",
	"InterfaceOptionsActionBarsPanelRight": &"multi_bar_3",
	"InterfaceOptionsActionBarsPanelRightTwo": &"multi_bar_4",
	"InterfaceOptionsSocialPanelChatBubbles": &"chat_bubbles",
	"InterfaceOptionsSocialPanelPartyChat": &"party_chat_bubbles",
	"InterfaceOptionsBuffsPanelBuffDurations": &"show_buff_durations",
	"InterfaceOptionsObjectivesPanelInstantQuestText": &"instant_quest_text",
	"InterfaceOptionsObjectivesPanelAutoQuestTracking": &"auto_quest_watch",
}
# The global string that names each check button, from InterfaceOptionsPanels.lua.
const CHECK_TEXTS: Dictionary[String, String] = {
	"InterfaceOptionsMousePanelInvertMouse": "INVERT_MOUSE",
	"InterfaceOptionsDisplayPanelShowHelm": "SHOW_HELM",
	"InterfaceOptionsDisplayPanelShowCloak": "SHOW_CLOAK",
	"InterfaceOptionsNamesPanelFriendlyPlayerNames": "UNIT_NAME_FRIENDLY",
	"InterfaceOptionsNamesPanelNPCNames": "UNIT_NAME_NPC",
	"InterfaceOptionsNamesPanelMyName": "UNIT_NAME_OWN",
	"InterfaceOptionsHelpPanelShowTutorials": "SHOW_TUTORIALS",
	"InterfaceOptionsHelpPanelLoadingScreenTips": "SHOW_TIPOFTHEDAY_TEXT",
	"InterfaceOptionsActionBarsPanelBottomLeft": "SHOW_MULTIBAR1_TEXT",
	"InterfaceOptionsActionBarsPanelBottomRight": "SHOW_MULTIBAR2_TEXT",
	"InterfaceOptionsActionBarsPanelRight": "SHOW_MULTIBAR3_TEXT",
	"InterfaceOptionsActionBarsPanelRightTwo": "SHOW_MULTIBAR4_TEXT",
	"InterfaceOptionsSocialPanelChatBubbles": "CHAT_BUBBLES_TEXT",
	"InterfaceOptionsSocialPanelPartyChat": "PARTY_CHAT_BUBBLES_TEXT",
	"InterfaceOptionsBuffsPanelBuffDurations": "SHOW_BUFF_DURATION_TEXT",
	"InterfaceOptionsObjectivesPanelInstantQuestText": "SHOW_QUEST_FADING_TEXT",
	"InterfaceOptionsObjectivesPanelAutoQuestTracking": "AUTO_QUEST_WATCH_TEXT",
}

# What the options stood at when the window opened, so Cancel can put them back.
var _opened: Dictionary[StringName, bool] = {}
var _accepted: bool = false


func _ready() -> void:
	for key: String in CHECK_OPTIONS:
		var check: WowButton = _check(key)
		(check.get_node(key + "Text") as Label).text = WowStrings.get_text(CHECK_TEXTS[key])
		check.pressed.connect(_on_check_pressed.bind(key))
	%InterfaceOptionsHelpPanelResetTutorials.pressed.connect(
		WowClient.session.send_packet.bind("CMSG_TUTORIAL_RESET", PackedByteArray())
	)
	%InterfaceOptionsFrameOkay.pressed.connect(_on_okay_pressed)
	%InterfaceOptionsFrameCancel.pressed.connect(close_requested.emit)
	%InterfaceOptionsFrameDefaults.pressed.connect(_on_defaults_pressed)
	visibility_changed.connect(_on_visibility_changed)


func _check(key: String) -> WowButton:
	return get_node("%" + key)


func _refresh() -> void:
	var settings: InterfaceSettings = WowAssets.interface
	for key: String in CHECK_OPTIONS:
		_check(key).checked = settings.is_on(CHECK_OPTIONS[key])


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


func _on_check_pressed(key: String) -> void:
	var option: StringName = CHECK_OPTIONS[key]
	WowAssets.interface.set_on(option, not WowAssets.interface.is_on(option))
	_refresh()


func _on_okay_pressed() -> void:
	_accepted = true
	WowAssets.interface.save()
	close_requested.emit()


func _on_defaults_pressed() -> void:
	WowAssets.interface.restore_defaults()
	_refresh()
