class_name LFDRoleCheckPopup
extends Control

const ROLE_BUTTONS: Dictionary[DungeonFinder.Role, String] = {
	DungeonFinder.Role.TANK: "LFDRoleCheckPopupRoleButtonTank",
	DungeonFinder.Role.HEALER: "LFDRoleCheckPopupRoleButtonHealer",
	DungeonFinder.Role.DAMAGE: "LFDRoleCheckPopupRoleButtonDPS",
}

var roles: int = DungeonFinder.Role.DAMAGE

@onready var _finder: DungeonFinder = WowClient.dungeon_finder


func _ready() -> void:
	for role: DungeonFinder.Role in ROLE_BUTTONS:
		var button: BaseButton = get_node("%" + ROLE_BUTTONS[role])
		button.pressed.connect(_toggle_role.bind(role))
		(button.get_node("CheckButton") as BaseButton).pressed.connect(_toggle_role.bind(role))
		LFGArt.icon(button.get_node("NormalTexture"), role)
	%LFDRoleCheckPopupAcceptButton.pressed.connect(_answer.bind(true))
	%LFDRoleCheckPopupDeclineButton.pressed.connect(_answer.bind(false))
	_finder.role_check_started.connect(_on_role_check_started)
	_finder.changed.connect(_on_changed)


func _refresh() -> void:
	var available: int = _finder.available_roles()
	roles &= available
	for role: DungeonFinder.Role in ROLE_BUTTONS:
		var button: BaseButton = get_node("%" + ROLE_BUTTONS[role])
		LFGArt.set_role_available(button, available & role != 0)
		(button.get_node("CheckButton") as WowButton).checked = roles & role != 0
	%LFDRoleCheckPopupAcceptButton.disabled = roles == 0
	var dungeons: Array[int] = _finder.role_check_dungeons
	var dungeon_name: String = WowStrings.get_text("MULTIPLE_DUNGEONS")
	if dungeons.size() == 1:
		dungeon_name = _finder.dungeon_name(dungeons[0])
	%LFDRoleCheckPopupDescriptionText.text = \
			WowStrings.get_text("QUEUED_FOR").replace("%s", dungeon_name)


func _toggle_role(role: DungeonFinder.Role) -> void:
	roles ^= role
	_refresh()


func _answer(accept: bool) -> void:
	_finder.set_roles(roles if accept else 0)
	hide()


func _on_role_check_started() -> void:
	show()
	_refresh()


func _on_changed() -> void:
	if _finder.state != DungeonFinder.State.ROLE_CHECK:
		hide()
