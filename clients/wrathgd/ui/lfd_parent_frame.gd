class_name LFDParentFrame
extends Control

signal close_requested

const ROLE_BUTTONS: Dictionary[DungeonFinder.Role, String] = {
	DungeonFinder.Role.TANK: "LFDQueueFrameRoleButtonTank",
	DungeonFinder.Role.HEALER: "LFDQueueFrameRoleButtonHealer",
	DungeonFinder.Role.DAMAGE: "LFDQueueFrameRoleButtonDPS",
	DungeonFinder.Role.LEADER: "LFDQueueFrameRoleButtonLeader",
}
var roles: int = DungeonFinder.Role.DAMAGE

@onready var _finder: DungeonFinder = WowClient.dungeon_finder


func _ready() -> void:
	for role: DungeonFinder.Role in ROLE_BUTTONS:
		var button: BaseButton = get_node("%" + ROLE_BUTTONS[role])
		button.pressed.connect(_toggle_role.bind(role))
		(button.get_node("CheckButton") as BaseButton).pressed.connect(_toggle_role.bind(role))
		LFGArt.icon(button.get_node("NormalTexture"), role)
		if role != DungeonFinder.Role.LEADER:
			LFGArt.background(get_node("%" + ROLE_BUTTONS[role] + "Background"), role)
	$Button.pressed.connect(close_requested.emit)
	%LFDQueueFrameCancelButton.pressed.connect(close_requested.emit)
	%LFDQueueFrameFindGroupButton.pressed.connect(_on_find_group_pressed)
	LFGArt.eye(%LFDParentFramePortraitTexture)
	%LFDQueueFrameTypeDropDownButton.hide()
	%LFDQueueFrameRandom.show()
	%LFDQueueFrameSpecific.hide()
	_finder.changed.connect(refresh)
	visibility_changed.connect(_on_visibility_changed)


func refresh() -> void:
	if not visible:
		return
	var available: int = _finder.available_roles()
	var idle: bool = _finder.state == DungeonFinder.State.NONE
	roles &= available
	for role: DungeonFinder.Role in ROLE_BUTTONS:
		var button: BaseButton = get_node("%" + ROLE_BUTTONS[role])
		var check: WowButton = button.get_node("CheckButton")
		LFGArt.set_role_available(button, available & role != 0)
		check.disabled = available & role == 0 or not idle
		check.checked = roles & role != 0
	var dungeon: Dictionary = _dungeon()
	var entry: int = dungeon.get("entry", 0)
	%LFDQueueFrameTypeDropDownText.text = _finder.dungeon_name(entry) if entry else ""
	_show_rewards(dungeon)
	var find: BaseButton = %LFDQueueFrameFindGroupButton
	find.disabled = entry == 0 or (idle and roles & ~DungeonFinder.Role.LEADER == 0)
	%LFDQueueFrameFindGroupButtonText.text = WowStrings.get_text(
		"FIND_A_GROUP" if idle else "LEAVE_QUEUE"
	)


# LFDQueueFrameRandom_UpdateFrame: each shown part stacks under the one before it.
func _show_rewards(dungeon: Dictionary) -> void:
	var prefix: String = "%LFDQueueFrameRandomScrollFrameChildFrame"
	var rewards_description: Label = get_node(prefix + "RewardsDescription")
	rewards_description.text = WowStrings.get_text(
		"LFD_RANDOM_REWARD_EXPLANATION2" if dungeon.get("done", false)
		else "LFD_RANDOM_REWARD_EXPLANATION1"
	)
	var items: Array = dungeon.get("items", [])
	var item_button: Control = get_node(prefix + "Item1")
	item_button.visible = not items.is_empty()
	if not items.is_empty():
		var item: Dictionary = items[0]
		(get_node(prefix + "Item1IconTexture") as TextureRect).texture = \
				Inventory.display_icon(item["display"])
		var info: Dictionary = WowClient.session.get_item_info(item["item"])
		(get_node(prefix + "Item1Name") as Label).text = info.get("name", "")
		(get_node(prefix + "Item1Count") as Label).text = \
				str(item["count"]) if item["count"] > 1 else ""
	var money: int = dungeon.get("money", 0)
	var xp: int = dungeon.get("xp", 0)
	var money_label: Label = get_node(prefix + "MoneyLabel")
	var money_frame: MoneyFrame = get_node(prefix + "MoneyFrame")
	var xp_label: Label = get_node(prefix + "XPLabel")
	var xp_amount: Label = get_node(prefix + "XPAmount")
	money_label.visible = money > 0
	money_frame.visible = money > 0
	money_frame.set_money(money)
	xp_label.visible = xp > 0
	xp_amount.visible = xp > 0
	xp_amount.text = str(xp)
	get_node(prefix + "PUGDescription").hide()
	var stack: Array[Control] = [
		get_node(prefix + "Title"), get_node(prefix + "Description"),
		get_node(prefix + "RewardsLabel"), rewards_description, item_button, money_label, xp_label,
	]
	var bottom: float = 0.0
	for part: Control in stack:
		if not part.visible:
			continue
		if bottom > 0.0:
			part.position.y = bottom + (10.0 if part in [item_button, money_label] else 5.0)
		if part is Label:
			part.size.y = part.get_combined_minimum_size().y
		bottom = part.position.y + part.size.y
	for pair: Array in [[money_label, money_frame], [xp_label, xp_amount]]:
		var label: Label = pair[0]
		pair[1].position = Vector2(
			label.position.x + label.get_combined_minimum_size().x + 10.0,
			label.position.y + (label.size.y - pair[1].size.y) / 2.0,
		)


# The first random dungeon the server offers; the stock default of the type dropdown.
func _dungeon() -> Dictionary:
	for dungeon: Dictionary in _finder.random_dungeons:
		if not _finder.locks.has(dungeon["entry"]):
			return dungeon
	return {}


func _toggle_role(role: DungeonFinder.Role) -> void:
	roles ^= role
	refresh()


func _on_find_group_pressed() -> void:
	if _finder.state != DungeonFinder.State.NONE:
		_finder.leave()
		return
	var entries: Array[int] = [_dungeon()["entry"]]
	_finder.join(roles, entries)


func _on_visibility_changed() -> void:
	if visible:
		_finder.request_info()
		refresh()
