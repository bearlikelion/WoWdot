class_name PanelManager
extends Control

signal bag_opened(bag: int, is_open: bool)

enum Area { LEFT, CENTER, FULL }

# UIParent's left and center panel spots.
const LEFT_POSITION: Vector2 = Vector2(0.0, 104.0)
const CENTER_POSITION: Vector2 = Vector2(384.0, 104.0)
# UIPanelWindows: where each panel opens and how readily it moves aside for another.
const ITEM_TEXT_SCENE: String = "res://ui/item_text_frame.tscn"
const PANELS: Dictionary[StringName, Array] = {
	&"CharacterFrame": [Area.LEFT, 2],
	&"SpellBookFrame": [Area.LEFT, 0],
	&"TalentFrame": [Area.LEFT, 6],
	&"QuestLogFrame": [Area.LEFT, 0],
	&"GossipFrame": [Area.LEFT, 0],
	&"QuestFrame": [Area.LEFT, 0],
	&"MerchantFrame": [Area.LEFT, 0],
	&"BankFrame": [Area.LEFT, 0],
	&"PetStableFrame": [Area.LEFT, 0],
	&"MailFrame": [Area.LEFT, 0],
	&"AuctionFrame": [Area.LEFT, 0],
	&"GuildRegistrarFrame": [Area.LEFT, 0],
	&"PetitionFrame": [Area.LEFT, 0],
	&"TabardFrame": [Area.LEFT, 0],
	&"TradeFrame": [Area.CENTER, 0],
	&"FriendsFrame": [Area.LEFT, 0],
	&"OpenMailFrame": [Area.CENTER, 0],
	&"ItemTextFrame": [Area.LEFT, 0],
	&"ClassTrainerFrame": [Area.LEFT, 0],
	&"TradeSkillFrame": [Area.LEFT, 0],
	&"DressUpFrame": [Area.LEFT, 0],
	&"InspectFrame": [Area.LEFT, 0],
	&"MacroFrame": [Area.LEFT, 0],
	&"LFDParentFrame": [Area.LEFT, 0],
	&"AchievementFrame": [Area.LEFT, 0],
	&"PVPParentFrame": [Area.LEFT, 0],
	&"GuildBankFrame": [Area.LEFT, 0],
	&"BattlefieldFrame": [Area.LEFT, 0],
	&"WorldStateScoreFrame": [Area.CENTER, 0],
	&"HelpFrame": [Area.CENTER, 0],
	&"TaxiFrame": [Area.LEFT, 0],
	&"LootFrame": [Area.LEFT, 0],
	&"WorldMapFrame": [Area.FULL, 0],
	&"GameMenuFrame": [Area.CENTER, 0],
	&"SoundOptionsFrame": [Area.CENTER, 0],
	&"VideoOptionsFrame": [Area.CENTER, 0],
	&"UIOptionsFrame": [Area.CENTER, 0],
	&"KeyBindingFrame": [Area.CENTER, 0],
}
# updateContainerFrameAnchors: bags stack up from the bottom right, starting a new column when full.
const BAG_OFFSET_Y: float = 70.0
const BAG_SPACING: float = 3.0
const BAG_WIDTH: float = 192.0

var _left: Control
var _center: Control
var _full: Control
# Open container frames in the order they opened, which is the order they stack.
var _bag_stack: Array[ContainerFrame] = []

# One frame per bag the player can open: the backpack, four worn bags and six bank bags.
@onready var _containers: Array[ContainerFrame] = [
	%ContainerFrame1, %ContainerFrame2, %ContainerFrame3, %ContainerFrame4, %ContainerFrame5,
	%ContainerFrame6, %ContainerFrame7, %ContainerFrame8, %ContainerFrame9, %ContainerFrame10,
	%ContainerFrame11,
]


func _ready() -> void:
	resized.connect(_place_bags)
	# A client that has not converted this window yet goes without it.
	if ResourceLoader.exists(ITEM_TEXT_SCENE):
		var reader: Control = (load(ITEM_TEXT_SCENE) as PackedScene).instantiate()
		add_child(reader)
		reader.owner = self
		reader.unique_name_in_owner = true
	for panel: StringName in PANELS:
		var frame: Control = get_node_or_null("%" + panel)
		if frame == null:
			continue
		frame.close_requested.connect(hide_panel.bind(frame))
	%GameMenuFrame.sound_options_requested.connect(show_panel.bind(%SoundOptionsFrame))
	%SoundOptionsFrame.close_requested.connect(show_panel.bind(%GameMenuFrame))
	%GameMenuFrame.video_options_requested.connect(show_panel.bind(%VideoOptionsFrame))
	%VideoOptionsFrame.close_requested.connect(show_panel.bind(%GameMenuFrame))
	%GameMenuFrame.interface_options_requested.connect(show_panel.bind(%UIOptionsFrame))
	%UIOptionsFrame.close_requested.connect(show_panel.bind(%GameMenuFrame))
	%GameMenuFrame.key_bindings_requested.connect(show_panel.bind(%KeyBindingFrame))
	%MacroFrame.open_requested.connect(show_panel.bind(%MacroFrame))
	%BattlefieldFrame.open_requested.connect(show_panel.bind(%BattlefieldFrame))
	%WorldStateScoreFrame.open_requested.connect(show_panel.bind(%WorldStateScoreFrame))
	%KeyBindingFrame.close_requested.connect(show_panel.bind(%GameMenuFrame))
	for container: ContainerFrame in _containers:
		container.closed.connect(_on_bag_closed.bind(container))


# PanelTemplates_SelectTab and PanelTemplates_DeselectTab.
static func select_tab(tab: Control, selected: bool) -> void:
	for piece: String in ["Left", "Middle", "Right"]:
		(tab.get_node(tab.name + piece) as CanvasItem).visible = not selected
		(tab.get_node(tab.name + piece + "Disabled") as CanvasItem).visible = selected
	var label: Label = tab.get_node(tab.name + "Text")
	label.theme_type_variation = &"GameFontHighlightSmall" if selected else &"GameFontNormalSmall"


# PanelTemplates_TabResize: the middle piece grows to the tab's text plus padding.
static func resize_tab(tab: Control, padding: float) -> void:
	var text: Label = tab.get_node(tab.name + "Text")
	var left: Control = tab.get_node(tab.name + "Left")
	var text_width: float = text.get_minimum_size().x
	var width: float = text_width + padding
	for suffix: String in ["", "Disabled"]:
		var middle: Control = tab.get_node_or_null(NodePath(tab.name + "Middle" + suffix))
		if middle:
			middle.size.x = width
			(tab.get_node(tab.name + "Right" + suffix) as Control).position.x = left.size.x + width
	tab.size.x = width + 2.0 * left.size.x
	text.size.x = text_width
	text.position.x = (tab.size.x - text_width) / 2.0
	var highlight: Control = tab.get_node_or_null("HighlightTexture")
	if highlight == null:
		return
	highlight.size.x = tab.size.x - 2.0 * highlight.position.x


func toggle_panel(frame: Control) -> void:
	if frame.visible:
		hide_panel(frame)
	else:
		show_panel(frame)


# ShowUIPanel: centre panels replace everything, left panels share the two spots by push priority.
func show_panel(frame: Control) -> void:
	if frame.visible:
		return
	var info: Array = PANELS[frame.name]
	var area: Area = info[0]
	if _full and area != Area.FULL:
		return
	if _center and _area(_center) == Area.CENTER and area != Area.CENTER:
		return
	match area:
		Area.FULL:
			close_all_windows()
			_full = frame
			frame.show()
			return
		Area.CENTER:
			close_windows()
			close_all_bags()
			_set_center(frame, false)
			return
	if _left == null:
		_set_left(frame)
	elif _center == null:
		if _pushable(_left) == 0 and info[1] == 0:
			_set_left(frame)
		elif _pushable(_left) > info[1]:
			_move_left_to_center()
			_set_left(frame)
		else:
			_set_center(frame, true)
	elif info[1] > _pushable(_center):
		_move_center_to_left()
		_set_center(frame, true)
	else:
		_set_left(frame)


# HideUIPanel: a left panel closing lets a pushed-aside left panel return to the left spot.
func hide_panel(frame: Control) -> void:
	if not frame.visible:
		return
	if frame == _full:
		_full = null
	elif frame == _center:
		_center = null
	elif frame == _left:
		if _center and _area(_center) == Area.LEFT:
			frame.hide()
			_left = null
			_move_center_to_left()
			return
		_left = null
	frame.hide()


# CloseWindows: true when there was a panel to close.
func close_windows() -> bool:
	var found: bool = _left != null or _center != null or _full != null
	for frame: Control in [_left, _center, _full]:
		if frame:
			hide_panel(frame)
	return found


func close_all_windows() -> bool:
	var bags_open: bool = not _bag_stack.is_empty()
	close_all_bags()
	return close_windows() or bags_open


func toggle_bag(bag: int) -> void:
	var open: ContainerFrame = _open_frame(bag)
	if open:
		open.close()
	elif Inventory.container_size(bag) > 0:
		_open_bag(bag)


# ToggleBackpack: with the backpack open it closes every bag, as the stock key does.
func toggle_backpack() -> void:
	if _open_frame(Inventory.BACKPACK):
		close_all_bags()
	else:
		toggle_bag(Inventory.BACKPACK)


# OpenAllBags: opens the backpack and every bag, or closes them all when they are all open.
# OpenBackpack and CloseBackpack, as merchants use them.
func set_backpack_open(is_open: bool) -> void:
	var frame: ContainerFrame = _open_frame(Inventory.BACKPACK)
	if is_open and frame == null:
		_open_bag(Inventory.BACKPACK)
	elif not is_open and frame:
		frame.close()


func open_all_bags() -> void:
	var total: int = 1
	for bag: int in range(1, Inventory.BAG_COUNT + 1):
		total += int(Inventory.container_size(bag) > 0)
	var open_count: int = _bag_stack.size()
	close_all_bags()
	if open_count >= total:
		return
	for bag: int in range(Inventory.BAG_COUNT + 1):
		if Inventory.container_size(bag) > 0:
			_open_bag(bag)


func close_all_bags() -> void:
	for container: ContainerFrame in _bag_stack.duplicate():
		container.close()


# A bank bag cannot be reached once the vault closes, so its frame goes with it.
func close_bank_bags() -> void:
	for container: ContainerFrame in _bag_stack.duplicate():
		if container.bag >= Inventory.BANK_BAG_FIRST:
			container.close()


func refresh_bags() -> void:
	for container: ContainerFrame in _bag_stack:
		container.refresh()


func _open_bag(bag: int) -> void:
	for container: ContainerFrame in _containers:
		if not container.visible:
			container.open(bag)
			_bag_stack.append(container)
			_place_bags()
			bag_opened.emit(bag, true)
			return


func _open_frame(bag: int) -> ContainerFrame:
	for container: ContainerFrame in _bag_stack:
		if container.bag == bag:
			return container
	return null


func _place_bags() -> void:
	var column: int = 0
	var bottom: float = size.y - BAG_OFFSET_Y
	for container: ContainerFrame in _bag_stack:
		if bottom - container.size.y < 0.0 and bottom < size.y - BAG_OFFSET_Y:
			column += 1
			bottom = size.y - BAG_OFFSET_Y
		container.position = Vector2(
			size.x - BAG_WIDTH * (column + 1), bottom - container.size.y
		)
		bottom -= container.size.y + BAG_SPACING


func _on_bag_closed(bag: int, container: ContainerFrame) -> void:
	_bag_stack.erase(container)
	_place_bags()
	bag_opened.emit(bag, false)


func _area(frame: Control) -> Area:
	return PANELS[frame.name][0]


func _pushable(frame: Control) -> int:
	return PANELS[frame.name][1]


func _set_left(frame: Control) -> void:
	if _left:
		_left.hide()
	_left = frame
	frame.position = LEFT_POSITION
	frame.show()


func _set_center(frame: Control, place: bool) -> void:
	if _center:
		_center.hide()
	_center = frame
	if place:
		frame.position = CENTER_POSITION
	frame.show()


func _move_left_to_center() -> void:
	if _center:
		_center.hide()
	_center = _left
	_left = null
	_center.position = CENTER_POSITION


func _move_center_to_left() -> void:
	if _left:
		_left.hide()
	_left = _center
	_center = null
	_left.position = LEFT_POSITION
