class_name SideActionBars
extends Control

signal action_used(slot: int)

# ActionBar pages 3 and 4, as MultiActionBars.lua lays them out.
const RIGHT_FIRST_SLOT: int = 24
const LEFT_FIRST_SLOT: int = 36

var _right: Array[ActionButton] = []
var _left: Array[ActionButton] = []

@onready var _left_bar: Control = %MultiBarLeft


func _ready() -> void:
	_right = MultiActionBar.bind(self, RIGHT_FIRST_SLOT, action_used.emit)
	_left = MultiActionBar.bind(_left_bar, LEFT_FIRST_SLOT, action_used.emit)
	WowClient.session.action_buttons_changed.connect(_update_visibility)
	WowAssets.interface.changed.connect(_update_visibility)
	_update_visibility()


func _update_visibility() -> void:
	MultiActionBar.update_visibility(self, _right, &"multi_bar_3")
	# MultiBarLeft is grafted under MultiBarRight, so it only shows alongside it as in the stock UI.
	MultiActionBar.update_visibility(_left_bar, _left, &"multi_bar_4")
